// relatorio_service.dart
import 'dart:convert';
import 'dart:io';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:file_saver/file_saver.dart';
import 'package:intl/intl.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:flutter_file_dialog/flutter_file_dialog.dart';
// PDF
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

class ReportResult {
  final String pdfPath;
  final String csvTimelinePath;
  final String csvResumoTratPath;

  ReportResult({
    required this.pdfPath,
    required this.csvTimelinePath,
    required this.csvResumoTratPath,
  });

  List<String> selectedPaths({
    required bool pdf,
    required bool csvTimeline,
    required bool csvResumo,
  }) {
    final paths = <String>[];
    if (pdf && pdfPath.isNotEmpty) paths.add(pdfPath);
    if (csvTimeline && csvTimelinePath.isNotEmpty) paths.add(csvTimelinePath);
    if (csvResumo && csvResumoTratPath.isNotEmpty) paths.add(csvResumoTratPath);
    return paths;
  }
}

class TimelineEvent {
  final DateTime quandoLocal;      // horário em localtime
  final String tipo;               // 'lembrete_tomado' | 'lembrete_adiado' | 'lembrete_cancelado' | 'sintoma' | 'lembrete'
  final String titulo;             // ex.: Nome do medicamento / Nome do sintoma
  final String detalhe;            // ex.: dosagem + observação
  final String? nomeTratamento;    // ex.: "Paracetamol 500mg"
  final String? statusLembrete;    // 'tomado'|'adiado'|'cancelado' (para lembretes)
  final DateTime? agendadoLocal;   // quando aplicável
  final DateTime? tomadoLocal;     // quando aplicável
  final int? atrasoMin;            // quando aplicável

  TimelineEvent({
    required this.quandoLocal,
    required this.tipo,
    required this.titulo,
    required this.detalhe,
    this.nomeTratamento,
    this.statusLembrete,
    this.agendadoLocal,
    this.tomadoLocal,
    this.atrasoMin,
  });
}

class RelatorioService {
  final _firestore = FirebaseFirestore.instance;
  final _dfDate = DateFormat('dd/MM/yyyy');
  final _dfDateTime = DateFormat('dd/MM/yyyy HH:mm');

  // =======================================================================
  // PÚBLICOS
  // =======================================================================

  /// Gera PDF/CSV(s) conforme flags e retorna os caminhos temporários.
  Future<ReportResult> gerarTimelineEResumo({
    required String idUsuario,
    required String nomeUsuario,
    required DateTime inicio,
    required DateTime fim,
    bool anonimizar = false,

    // O que gerar
    bool makePdf = true,
    bool makeCsvTimeline = true,
    bool makeCsvResumo = true,
  }) async {
    // Normaliza para consultas
    final start = inicio.toUtc();
    final end = fim.toUtc();

    // 1) Carrega TRATAMENTOS ATIVOS
    final tratamentosSnap = await _firestore
        .collection('usuarios').doc(idUsuario)
        .collection('tratamentos')
        .where('status', isEqualTo: 'ativo')
        .get();

    // Mapa rápido para enriquecer lembretes
    final Map<String, Map<String, dynamic>> tratMapById = {};
    for (final d in tratamentosSnap.docs) {
      final data = d.data();
      data['idTratamento'] = d.id;
      tratMapById[d.id] = data;
    }

    // 2) Carrega LEMBRETES (período)
    final lembretesQuery = _firestore
        .collection('usuarios').doc(idUsuario)
        .collection('lembretes')
        .where('dataHoraAgendado', isGreaterThanOrEqualTo: Timestamp.fromDate(start))
        .where('dataHoraAgendado', isLessThanOrEqualTo: Timestamp.fromDate(end))
        .orderBy('dataHoraAgendado');

    final lembretesSnap = await lembretesQuery.get();

    // 3) Carrega SINTOMAS (período)
    final sintomasSnap = await _firestore
        .collection('usuarios').doc(idUsuario)
        .collection('sintomas')
        .where('dataHora', isGreaterThanOrEqualTo: Timestamp.fromDate(start))
        .where('dataHora', isLessThanOrEqualTo: Timestamp.fromDate(end))
        .orderBy('dataHora')
        .get();

    // 4) Monta TIMELINE
    final timeline = <TimelineEvent>[];

    // Lembretes
    for (final d in lembretesSnap.docs) {
      final m = d.data();

      final DateTime agendado = (m['dataHoraAgendado'] as Timestamp).toDate().toLocal();
      final DateTime? tomado = (m['dataHoraTomado'] as Timestamp?)?.toDate().toLocal();
      final bool tomadoB = (m['tomado'] ?? false) as bool;
      final bool adiadoB = (m['adiado'] ?? false) as bool;
      final bool canceladoB = (m['cancelado'] ?? false) as bool;

      String status = '';
      if (canceladoB) status = 'cancelado';
      else if (adiadoB) status = 'adiado';
      else if (tomadoB) status = 'tomado';

      final String idTrat = (m['idTratamento'] ?? '').toString();
      final t = tratMapById[idTrat] ?? {};
      final String nomeMed = (t['nomeMedicamento'] ?? 'Tratamento').toString();
      final String conc = (t['concentracaoMedicamento'] ?? '').toString();
      final String dosagem = (t['dosagem'] ?? '').toString();

      int? atrasoMin;
      if (tomado != null) {
        atrasoMin = tomado.difference(agendado).inMinutes;
      }

      timeline.add(TimelineEvent(
        quandoLocal: tomado ?? agendado,
        tipo: status.isEmpty ? 'lembrete' : 'lembrete_$status',
        titulo: nomeMed.isEmpty ? 'Lembrete' : nomeMed,
        detalhe: [
          if (conc.isNotEmpty) conc,
          if (dosagem.isNotEmpty) 'Dose: $dosagem',
          if (status.isNotEmpty) 'Status: ${status.toUpperCase()}',
          'Agendado: ${_dfDateTime.format(agendado)}',
          if (tomado != null) 'Tomado: ${_dfDateTime.format(tomado)}',
          if (atrasoMin != null) 'Atraso: ${atrasoMin.abs()} min',
        ].join(' - '),
        nomeTratamento: nomeMed,
        statusLembrete: status.isEmpty ? null : status,
        agendadoLocal: agendado,
        tomadoLocal: tomado,
        atrasoMin: atrasoMin,
      ));
    }

    // Sintomas
    for (final d in sintomasSnap.docs) {
      final m = d.data();
      final DateTime quando = (m['dataHora'] as Timestamp).toDate().toLocal();
      final nome = (m['nome'] ?? 'Sintoma').toString();
      final intensidade = (m['intensidade'] ?? '').toString();
      final obs = (m['observacoes'] ?? '').toString();

      timeline.add(TimelineEvent(
        quandoLocal: quando,
        tipo: 'sintoma',
        titulo: nome,
        detalhe: [
          if (intensidade.isNotEmpty) 'Intensidade: $intensidade',
          if (obs.isNotEmpty) 'Obs.: $obs',
          'Data/Hora: ${_dfDateTime.format(quando)}',
        ].join(' - '),
      ));
    }

    timeline.sort((a, b) => a.quandoLocal.compareTo(b.quandoLocal));

    // 5) Gerar arquivos conforme flags
    final dir = await getTemporaryDirectory();
    final stamp = DateFormat('yyyyMMdd_HHmm').format(DateTime.now());

    String csvTimelinePath = '';
    String csvResumoPath = '';
    String pdfPath = '';

    if (makeCsvTimeline) {
      csvTimelinePath = '${dir.path}/alertaMED_timeline_$stamp.csv';
      await _gerarCsvTimeline(csvTimelinePath, timeline, separador: ';');
    }

    if (makeCsvResumo) {
      csvResumoPath = '${dir.path}/alertaMED_resumo_tratamentos_ativos_$stamp.csv';
      await _gerarCsvResumoTratamentos(
        csvResumoPath,
        tratamentosSnap.docs,
        separador: ';',
        anonimizar: anonimizar,
      );
    }

    if (makePdf) {
      pdfPath = '${dir.path}/alertaMED_relatorio_$stamp.pdf';
      await _gerarPdf(
        path: pdfPath,
        nomeUsuario: nomeUsuario,
        inicio: inicio,
        fim: fim,
        timeline: timeline,
        tratamentosAtivos: tratamentosSnap.docs.map((e) => e.data()).toList(),
        anonimizar: anonimizar,
      );
    }

    return ReportResult(
      pdfPath: pdfPath,
      csvTimelinePath: csvTimelinePath,
      csvResumoTratPath: csvResumoPath,
    );
  }

  /// Compartilha arquivos existentes via share_plus
  Future<void> compartilharArquivos({
    required List<String> paths,
    String? texto,
  }) async {
    final files = paths
        .where((p) => p.isNotEmpty && File(p).existsSync())
        .map((p) => XFile(p))
        .toList();
    if (files.isEmpty) return;
    await Share.shareXFiles(files, text: texto);
  }

  /// Salva os arquivos no dispositivo usando file_saver (MimeType enum)
  Future<void> salvarNoDispositivo({
    required List<String> paths,
  }) async {
    for (final path in paths) {
      final f = File(path);
      if (!await f.exists()) continue;

      final bytes = await f.readAsBytes();
      final ext = p.extension(path).toLowerCase(); // .pdf / .csv
      final base = p.basenameWithoutExtension(path);

      final mime = switch (ext) {
        '.pdf' => MimeType.pdf,
        '.csv' => MimeType.csv,
        '.txt' => MimeType.text,
        _ => MimeType.other,
      };

      await FileSaver.instance.saveFile(
        name: base,                                // sem extensão
        bytes: bytes,
        ext: ext.replaceFirst('.', ''),            // 'pdf' | 'csv' | ...
        mimeType: mime,
      );
    }
  }

  // =======================================================================
  // PRIVADOS — Geração de arquivos
  // =======================================================================


  Future<void> salvarComPicker({
    required List<String> paths,
  }) async {
    for (final path in paths) {
      final file = File(path);
      if (!await file.exists()) continue;

      final fileName = p.basename(path); // mantém extensão correta
      final params = SaveFileDialogParams(
        sourceFilePath: path,  // copia do temp p/ local escolhido
        fileName: fileName,    // sugere nome
      );

      // Abre o diálogo nativo (Android: SAF, iOS: UIDocumentPicker)
      final savedPath = await FlutterFileDialog.saveFile(params: params);

      // Opcional: feedback
      if (savedPath == null) {
        // usuário cancelou
      } else {
        // sucesso, savedPath é o destino final
      }
    }
  }

  Future<void> _gerarCsvTimeline(
      String path,
      List<TimelineEvent> events, {
        String separador = ';',
      }) async {
    final sink = File(path).openWrite(encoding: const Utf8Codec());
    // Cabeçalho
    sink.writeln([
      'tipo_evento',
      'titulo',
      'detalhe',
      'data_hora_local',
      'data_hora_utc',
      'status_lembrete',
      'agendado_local',
      'tomado_local',
      'atraso_min',
    ].join(separador));

    for (final e in events) {
      final localStr = _dfDateTime.format(e.quandoLocal);
      final utcStr = e.quandoLocal.toUtc().toIso8601String();
      final agLocal = e.agendadoLocal != null ? _dfDateTime.format(e.agendadoLocal!) : '';
      final tomLocal = e.tomadoLocal != null ? _dfDateTime.format(e.tomadoLocal!) : '';
      sink.writeln([
        e.tipo,
        _csvSafe(e.titulo),
        _csvSafe(e.detalhe),
        localStr,
        utcStr,
        e.statusLembrete ?? '',
        agLocal,
        tomLocal,
        e.atrasoMin?.toString() ?? '',
      ].join(separador));
    }
    await sink.flush();
    await sink.close();
  }

  Future<void> _gerarCsvResumoTratamentos(
      String path,
      List<QueryDocumentSnapshot<Map<String, dynamic>>> docs, {
        String separador = ';',
        bool anonimizar = false, // (mantido por compat, mas não usado aqui)
      }) async {
    final sink = File(path).openWrite(encoding: const Utf8Codec());
    sink.writeln([
      'nome_medicamento',
      'concentracao',
      'tipo_medicamento',
      'unidade_medida',
      'dosagem',
      'frequencia',
      'tipo_frequencia',
      'data_inicio_local',
      'data_termino_local',
      'tipo_tratamento',
      'observacoes',
      'status',
    ].join(separador));

    for (final d in docs) {
      final m = d.data();
      final di = (m['dataInicio'] as Timestamp?)?.toDate().toLocal();
      final dt = (m['dataTermino'] as Timestamp?)?.toDate().toLocal();
      sink.writeln([
        _csvSafe((m['nomeMedicamento'] ?? '').toString()),
        _csvSafe((m['concentracaoMedicamento'] ?? '').toString()),
        _csvSafe((m['tipoMedicamento'] ?? '').toString()),
        _csvSafe((m['unidadeMedida'] ?? '').toString()),
        _csvSafe((m['dosagem'] ?? '').toString()),
        _csvSafe((m['frequencia'] ?? '').toString()),
        _csvSafe((m['tipoFrequencia'] ?? '').toString()),
        di != null ? _dfDateTime.format(di) : '',
        dt != null ? _dfDateTime.format(dt) : '',
        _csvSafe((m['tipoTratamento'] ?? '').toString()),
        _csvSafe((m['observacoes'] ?? '').toString()),
        _csvSafe((m['status'] ?? '').toString()),
      ].join(separador));
    }
    await sink.flush();
    await sink.close();
  }

  Future<void> _gerarPdf({
    required String path,
    required String nomeUsuario,
    required DateTime inicio,
    required DateTime fim,
    required List<TimelineEvent> timeline,
    required List<Map<String, dynamic>> tratamentosAtivos,
    bool anonimizar = false,
  }) async {
    final pdf = pw.Document();

    final tituloUsuario = anonimizar ? 'Usuário (anônimo)' : nomeUsuario;
    final inicioStr = _dfDateTime.format(inicio.toLocal());
    final fimStr = _dfDateTime.format(fim.toLocal());

    // Resumos
    final totalLembretesTomados = timeline.where((e) => e.tipo == 'lembrete_tomado').length;
    final totalLembretesAdiados = timeline.where((e) => e.tipo == 'lembrete_adiado').length;
    final totalLembretesCancel = timeline.where((e) => e.tipo == 'lembrete_cancelado').length;
    final totalSintomas = timeline.where((e) => e.tipo == 'sintoma').length;

    pdf.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(28),
        build: (ctx) => [
          pw.Header(
            level: 0,
            child: pw.Text(
              'Relatório AlertaMED',
              style: pw.TextStyle(fontSize: 22, fontWeight: pw.FontWeight.bold),
            ),
          ),
          pw.Text('Paciente/Cuidador: $tituloUsuario'),
          pw.Text('Período: $inicioStr - $fimStr'),
          pw.SizedBox(height: 12),
          pw.Container(
            padding: const pw.EdgeInsets.all(10),
            decoration: pw.BoxDecoration(
              border: pw.Border.all(color: PdfColors.grey400),
              borderRadius: pw.BorderRadius.circular(6),
            ),
            child: pw.Row(
              mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
              children: [
                _chip('Tomados', totalLembretesTomados.toString()),
                _chip('Adiados', totalLembretesAdiados.toString()),
                _chip('Cancelados', totalLembretesCancel.toString()),
                _chip('Sintomas', totalSintomas.toString()),
                _chip('Trat. Ativos', tratamentosAtivos.length.toString()),
              ],
            ),
          ),
          pw.SizedBox(height: 16),
          pw.Text('Timeline de Eventos',
              style: pw.TextStyle(fontSize: 16, fontWeight: pw.FontWeight.bold)),
          pw.SizedBox(height: 6),
          _tabelaTimeline(timeline),

          pw.SizedBox(height: 18),
          pw.Text('Resumo de Tratamentos Ativos',
              style: pw.TextStyle(fontSize: 16, fontWeight: pw.FontWeight.bold)),
          pw.SizedBox(height: 6),
          _tabelaTratamentos(tratamentosAtivos),
        ],
      ),
    );

    final file = File(path);
    await file.writeAsBytes(await pdf.save());
  }

  // =======================================================================
  // Helpers PDF
  // =======================================================================

  pw.Widget _chip(String label, String value) {
    return pw.Container(
      padding: const pw.EdgeInsets.symmetric(vertical: 6, horizontal: 10),
      decoration: pw.BoxDecoration(
        color: PdfColors.grey200,
        borderRadius: pw.BorderRadius.circular(20),
      ),
      child: pw.Row(
        children: [
          pw.Text('$label: ', style: pw.TextStyle(fontWeight: pw.FontWeight.bold)),
          pw.Text(value),
        ],
      ),
    );
  }

  pw.Widget _tabelaTimeline(List<TimelineEvent> lista) {
    final headers = ['Data/Hora', 'Tipo', 'Título', 'Detalhe'];
    final data = lista.map((e) => [
      _dfDateTime.format(e.quandoLocal),
      _rotuloTipo(e.tipo),
      e.titulo,
      e.detalhe,
    ]).toList();

    return pw.Table.fromTextArray(
      headers: headers,
      data: data,
      headerStyle: pw.TextStyle(fontWeight: pw.FontWeight.bold),
      cellAlignment: pw.Alignment.centerLeft,
      headerDecoration: const pw.BoxDecoration(color: PdfColor.fromInt(0xFFEFEFEF)),
      cellPadding: const pw.EdgeInsets.symmetric(vertical: 4, horizontal: 4),
      columnWidths: {
        0: const pw.FixedColumnWidth(110),
        1: const pw.FixedColumnWidth(90),
      },
    );
  }

  pw.Widget _tabelaTratamentos(List<Map<String, dynamic>> ts) {
    final headers = [
      'Medicamento',
      'Concentração',
      'Tipo',
      'Dosagem',
      'Freq.',
      'Tipo Freq.',
      'Início',
      'Término',
      'Tipo Trat.',
      'Status'
    ];
    final data = ts.map((m) {
      final di = (m['dataInicio'] as Timestamp?)?.toDate().toLocal();
      final dt = (m['dataTermino'] as Timestamp?)?.toDate().toLocal();
      return [
        (m['nomeMedicamento'] ?? '').toString(),
        (m['concentracaoMedicamento'] ?? '').toString(),
        (m['tipoMedicamento'] ?? '').toString(),
        (m['dosagem'] ?? '').toString(),
        (m['frequencia'] ?? '').toString(),
        (m['tipoFrequencia'] ?? '').toString(),
        di != null ? _dfDateTime.format(di) : '',
        dt != null ? _dfDateTime.format(dt) : '',
        (m['tipoTratamento'] ?? '').toString(),
        (m['status'] ?? '').toString(),
      ];
    }).toList();

    return pw.Table.fromTextArray(
      headers: headers,
      data: data,
      headerStyle: pw.TextStyle(fontWeight: pw.FontWeight.bold),
      cellAlignment: pw.Alignment.centerLeft,
      headerDecoration: const pw.BoxDecoration(color: PdfColor.fromInt(0xFFEFEFEF)),
      cellPadding: const pw.EdgeInsets.symmetric(vertical: 4, horizontal: 4),
      columnWidths: {
        0: const pw.FixedColumnWidth(120),
        1: const pw.FixedColumnWidth(70),
        2: const pw.FixedColumnWidth(85),
        3: const pw.FixedColumnWidth(60),
        4: const pw.FixedColumnWidth(70),
      },
    );
  }

  String _rotuloTipo(String raw) {
    switch (raw) {
      case 'lembrete_tomado':
        return 'Lembrete (Tomado)';
      case 'lembrete_adiado':
        return 'Lembrete (Adiado)';
      case 'lembrete_cancelado':
        return 'Lembrete (Cancelado)';
      case 'sintoma':
        return 'Sintoma';
      default:
        return 'Lembrete';
    }
  }

  String _csvSafe(String s) {
    // Coloca entre aspas se tiver separador, aspas ou quebra de linha
    if (s.contains(';') || s.contains(',') || s.contains('\n') || s.contains('"')) {
      final escaped = s.replaceAll('"', '""');
      return '"$escaped"';
    }
    return s;
  }
}
