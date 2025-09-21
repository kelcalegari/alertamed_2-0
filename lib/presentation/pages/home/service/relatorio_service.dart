// relatorio_service.dart
import 'dart:convert';
import 'dart:io';

import 'package:file_saver/file_saver.dart';
import 'package:intl/intl.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:flutter_file_dialog/flutter_file_dialog.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

// Opcional: só para reconhecer Timestamp se os mapas do Provider vierem do Firestore
import 'package:cloud_firestore/cloud_firestore.dart' show Timestamp;

import '../../../../providers/user_data_provider.dart';



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
  final String titulo;             // ex.: nome do medicamento / sintoma
  final String detalhe;            // ex.: dosagem + observação
  final String? nomeTratamento;    // ex.: "Paracetamol 500mg"
  final String? statusLembrete;    // 'tomado'|'adiado'|'cancelado'
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
  final _dfDate = DateFormat('dd/MM/yyyy');
  final _dfDateTime = DateFormat('dd/MM/yyyy HH:mm');

  // =======================================================================
  // NOVO: Gera usando SOMENTE os dados do UsuarioProvider (contexto atual)
  // =======================================================================
  Future<ReportResult> gerarTimelineEResumo({
    required UsuarioProvider userProv,
    required DateTime inicio,
    required DateTime fim,
    String? nomeUsuario,
    bool anonimizar = false,

    // O que gerar
    bool makePdf = true,
    bool makeCsvTimeline = true,
    bool makeCsvResumo = true,
  }) async {
    // Pega o contexto do provider (paciente atual)
    final String ctxUid = userProv.contextoUsuarioId;

    // Nome do usuário para o relatório
    final nomeCtx = nomeUsuario ??
        (userProv.isContextoSouEu
            ? (userProv.dadosUsuario['nome']?.toString().trim().isNotEmpty == true
            ? userProv.dadosUsuario['nome'].toString()
            : 'Você')
            : 'Paciente');

    // Converte limites para UTC somente para comparação consistente
    final startUtc = inicio.toUtc();
    final endUtc = fim.toUtc();

    // ---------- TRATAMENTOS ATIVOS ----------
    // No provider, tratamentosMap = { idTratamento: Map }
    final List<Map<String, dynamic>> tratamentosAtivos =
    userProv.tratamentosMap.values
        .where((m) => (m['status'] ?? '') == 'ativo')
        .map((m) => Map<String, dynamic>.from(m))
        .toList();

    // Mapa rápido por idTratamento
    final Map<String, Map<String, dynamic>> tratMapById = {
      for (final entry in userProv.tratamentosMap.entries)
        entry.key: Map<String, dynamic>.from(entry.value),
    };

    // ---------- LEMBRETES (filtra por período do agendado) ----------
    final List<Map<String, dynamic>> lembretesPeriodo = userProv.lembretes.where((mRaw) {
      final m = Map<String, dynamic>.from(mRaw);
      final DateTime? ag = _toDate(m['dataHoraAgendado'])?.toUtc();
      if (ag == null) return false;
      return (ag.isAtSameMomentAs(startUtc) || ag.isAfter(startUtc)) &&
          (ag.isAtSameMomentAs(endUtc)   || ag.isBefore(endUtc));
    }).toList();

    // ---------- SINTOMAS (filtra por período) ----------
    final List<Map<String, dynamic>> sintomasPeriodo = userProv.sintomas.where((mRaw) {
      final m = Map<String, dynamic>.from(mRaw);
      final DateTime? dh = _toDate(m['dataHora'])?.toUtc();
      if (dh == null) return false;
      return (dh.isAtSameMomentAs(startUtc) || dh.isAfter(startUtc)) &&
          (dh.isAtSameMomentAs(endUtc)   || dh.isBefore(endUtc));
    }).toList();

    // ---------- MONTA TIMELINE ----------
    final timeline = <TimelineEvent>[];

    // Lembretes
    for (final mRaw in lembretesPeriodo) {
      final m = Map<String, dynamic>.from(mRaw);

      final DateTime? agendado = _toDate(m['dataHoraAgendado'])?.toLocal();
      final DateTime? tomado = _toDate(m['dataHoraTomado'])?.toLocal();

      final bool tomadoB    = (m['tomado'] ?? false) == true;
      final bool adiadoB    = (m['adiado'] ?? false) == true;
      final bool canceladoB = (m['cancelado'] ?? false) == true;

      String status = '';
      if (canceladoB)      status = 'cancelado';
      else if (adiadoB)    status = 'adiado';
      else if (tomadoB)    status = 'tomado';

      final String idTrat = (m['idTratamento'] ?? '').toString();
      final t = tratMapById[idTrat] ?? {};
      final String nomeMed = (t['nomeMedicamento'] ?? 'Tratamento').toString();
      final String conc    = (t['concentracaoMedicamento'] ?? '').toString();
      final String dosagem = (t['dosagem'] ?? '').toString();

      int? atrasoMin;
      if (tomado != null && agendado != null) {
        atrasoMin = tomado.difference(agendado).inMinutes;
      }

      timeline.add(TimelineEvent(
        quandoLocal: (tomado ?? agendado ?? DateTime.now()),
        tipo: status.isEmpty ? 'lembrete' : 'lembrete_$status',
        titulo: nomeMed.isEmpty ? 'Lembrete' : nomeMed,
        detalhe: [
          if (conc.isNotEmpty) conc,
          if (dosagem.isNotEmpty) 'Dose: $dosagem',
          if (status.isNotEmpty) 'Status: ${status.toUpperCase()}',
          if (agendado != null) 'Agendado: ${_dfDateTime.format(agendado)}',
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
    for (final mRaw in sintomasPeriodo) {
      final m = Map<String, dynamic>.from(mRaw);
      final DateTime quando = (_toDate(m['dataHora']) ?? DateTime.now()).toLocal();
      final nome        = (m['nome'] ?? 'Sintoma').toString();
      final intensidade = (m['intensidade'] ?? '').toString();
      final obs         = (m['observacoes'] ?? '').toString();

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

    // ---------- Geração de arquivos ----------
    final dir = await getTemporaryDirectory();
    final stamp = DateFormat('yyyyMMdd_HHmm').format(DateTime.now());

    String csvTimelinePath = '';
    String csvResumoPath   = '';
    String pdfPath         = '';

    if (makeCsvTimeline) {
      csvTimelinePath = '${dir.path}/alertaMED_timeline_$stamp.csv';
      await _gerarCsvTimeline(csvTimelinePath, timeline, separador: ';');
    }

    if (makeCsvResumo) {
      csvResumoPath = '${dir.path}/alertaMED_resumo_tratamentos_ativos_$stamp.csv';
      await _gerarCsvResumoTratamentos(
        csvResumoPath,
        tratamentosAtivos,
        separador: ';',
        anonimizar: anonimizar,
      );
    }

    if (makePdf) {
      pdfPath = '${dir.path}/alertaMED_relatorio_$stamp.pdf';
      await _gerarPdf(
        path: pdfPath,
        nomeUsuario: nomeCtx,
        inicio: inicio,
        fim: fim,
        timeline: timeline,
        tratamentosAtivos: tratamentosAtivos,
        anonimizar: anonimizar,
      );
    }

    return ReportResult(
      pdfPath: pdfPath,
      csvTimelinePath: csvTimelinePath,
      csvResumoTratPath: csvResumoPath,
    );
  }

  // =======================================================================
  // Compartilhamento / Salvamento (inalterados)
  // =======================================================================

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
        name: base,
        bytes: bytes,
        ext: ext.replaceFirst('.', ''),
        mimeType: mime,
      );
    }
  }

  Future<void> salvarComPicker({
    required List<String> paths,
  }) async {
    for (final path in paths) {
      final file = File(path);
      if (!await file.exists()) continue;

      final fileName = p.basename(path);
      final params = SaveFileDialogParams(
        sourceFilePath: path,
        fileName: fileName,
      );

      await FlutterFileDialog.saveFile(params: params);
    }
  }

  // =======================================================================
  // CSV / PDF
  // =======================================================================

  Future<void> _gerarCsvTimeline(
      String path,
      List<TimelineEvent> events, {
        String separador = ';',
      }) async {
    final sink = File(path).openWrite(encoding: const Utf8Codec());
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
      List<Map<String, dynamic>> tratamentosAtivos, {
        String separador = ';',
        bool anonimizar = false, // mantido por compat
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

    for (final m in tratamentosAtivos) {
      final di = _toDate(m['dataInicio'])?.toLocal();
      final dt = _toDate(m['dataTermino'])?.toLocal();
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

    final totalLembretesTomados = timeline.where((e) => e.tipo == 'lembrete_tomado').length;
    final totalLembretesAdiados = timeline.where((e) => e.tipo == 'lembrete_adiado').length;
    final totalLembretesCancel  = timeline.where((e) => e.tipo == 'lembrete_cancelado').length;
    final totalSintomas         = timeline.where((e) => e.tipo == 'sintoma').length;

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
          pw.Text('Nome'
              ': $tituloUsuario'),
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
      final di = _toDate(m['dataInicio'])?.toLocal();
      final dt = _toDate(m['dataTermino'])?.toLocal();
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
    if (s.contains(';') || s.contains(',') || s.contains('\n') || s.contains('"')) {
      final escaped = s.replaceAll('"', '""');
      return '"$escaped"';
    }
    return s;
  }

  // =======================================================================
  // Util: converter dinamicamente para DateTime
  // =======================================================================
  DateTime? _toDate(dynamic v) {
    if (v == null) return null;
    if (v is DateTime) return v;
    if (v is Timestamp) return v.toDate();
    if (v is int) {
      // se vier epoch millis
      try {
        return DateTime.fromMillisecondsSinceEpoch(v, isUtc: false);
      } catch (_) {}
    }
    if (v is String) {
      try {
        return DateTime.parse(v);
      } catch (_) {}
    }
    return null;
  }
}
