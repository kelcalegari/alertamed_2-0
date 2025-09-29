import 'package:flutter/material.dart';
import '../../themes/app_colors.dart';

class CustomTextField extends StatefulWidget {
  final TextEditingController ctrl;
  final String? label;
  final String? hint;
  final IconData? icon;
  final TextInputType textInputType;
  final bool isPassword;
  final bool isTime;
  final double pad;
  final int maxLength;
  final int maxLines;
  final double fontSize;
  final String? Function(String?)? validador;
  final FocusNode? focusNode;
  final void Function()? onComplete;
  final void Function(PointerDownEvent)? onTapOutside;
  final void Function(TimeOfDay time)? onTimePicked;
  final void Function(DateTime date)? onDatePicked;
  final TimeOfDay? initialTime;
  final Widget? bottom;            // NOVO: conteúdo logo abaixo do campo
  final double bottomSpacing;      // NOVO: espaço entre campo e bottom

  // >>> NOVOS (opcionais)
  final bool? readOnly;          // se null, aplica lógica padrão (data/hora = readOnly)
  final VoidCallback? onTap;     // se null, aplica pickers quando for data/hora
  final ValueChanged<String>? onChanged;
  const CustomTextField({
    super.key,
    required this.ctrl,
    this.label,
    this.hint,
    required this.textInputType,
    this.icon,
    this.isPassword = false,
    this.isTime = false,
    this.pad = 20,
    this.maxLength = -1,
    this.maxLines = 1,
    this.fontSize = 20,
    this.validador,
    this.focusNode,
    this.onComplete,
    this.onTapOutside,
    this.initialTime,
    this.onTimePicked,
    this.onDatePicked,
    this.readOnly,       // novo
    this.onTap, this.onChanged,          // novo
    this.bottom,
    this.bottomSpacing = 6,
  });

  @override
  State<CustomTextField> createState() => _CustomTextFieldState();
}

class _CustomTextFieldState extends State<CustomTextField> {
  bool _passVisible = false;

  @override
  Widget build(BuildContext context) {
    final bool isDateField = widget.textInputType == TextInputType.datetime;
    final bool defaultReadOnly = isDateField || widget.isTime;
    final bool effectiveReadOnly = widget.readOnly ?? defaultReadOnly;

    return Padding(
      padding: EdgeInsets.symmetric(horizontal: widget.pad),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          TextFormField(
            focusNode: widget.focusNode,
            controller: widget.ctrl,
            keyboardType: widget.textInputType,
            textCapitalization:
            widget.isPassword ? TextCapitalization.none : TextCapitalization.sentences,
            maxLength: widget.maxLength > 0 ? widget.maxLength : null,
            maxLines: widget.maxLines,
            obscureText: widget.isPassword && !_passVisible,
            validator: widget.validador,
            style: TextStyle(fontSize: widget.fontSize, color: AppColors.textVerde),

            // >>> READONLY opcional
            readOnly: effectiveReadOnly,

            // >>> ONTAP opcional (se fornecido, usa ele; senão mantém os pickers para data/hora)
            onTap: widget.onTap ??
                ((isDateField || widget.isTime)
                    ? () async {
                  if (isDateField) {
                    // --- DATE PICKER ---
                    DateTime initialDate;
                    try {
                      final parts = widget.ctrl.text.split('/');
                      if (parts.length == 3) {
                        final day = int.parse(parts[0]);
                        final month = int.parse(parts[1]);
                        final year = int.parse(parts[2]);
                        initialDate = DateTime(year, month, day);
                      } else {
                        initialDate = DateTime.now();
                      }
                    } catch (_) {
                      initialDate = DateTime.now();
                    }

                    final picked = await showDatePicker(
                      context: context,
                      initialDate: initialDate,
                      firstDate: DateTime(1900),
                      lastDate: DateTime(2100),
                    );
                    if (picked != null) {
                      widget.ctrl.text =
                      "${picked.day.toString().padLeft(2, '0')}/"
                          "${picked.month.toString().padLeft(2, '0')}/"
                          "${picked.year}";
                      widget.onDatePicked?.call(picked);
                      widget.onChanged?.call(widget.ctrl.text);

                      widget.onComplete?.call();
                      FocusScope.of(context).unfocus();
                    }
                  } else if (widget.isTime) {
                    // --- TIME PICKER (24h + HH:mm) ---
                    TimeOfDay initial = widget.initialTime ??
                        (() {
                          final t = widget.ctrl.text.trim();
                          final p = t.split(':');
                          if (p.length == 2) {
                            final h = int.tryParse(p[0]);
                            final m = int.tryParse(p[1]);
                            if (h != null && m != null) {
                              return TimeOfDay(hour: h, minute: m);
                            }
                          }
                          return TimeOfDay.now();
                        })();

                    final picked = await showTimePicker(
                      context: context,
                      initialTime: initial,
                      builder: (ctx, child) {
                        return MediaQuery(
                          data: MediaQuery.of(ctx).copyWith(alwaysUse24HourFormat: true),
                          child: child!,
                        );
                      },
                    );

                    if (picked != null) {
                      final hh = picked.hour.toString().padLeft(2, '0');
                      final mm = picked.minute.toString().padLeft(2, '0');
                      widget.ctrl.text = "$hh:$mm";
                      widget.onTimePicked?.call(picked);
                      widget.onChanged?.call(widget.ctrl.text);
                      widget.onComplete?.call();
                      FocusScope.of(context).unfocus();
                    }
                  }
                }
                    : null),

            decoration: InputDecoration(
              isDense: true,
              contentPadding: const EdgeInsets.symmetric(
                vertical: 15,
                horizontal: 8,
              ),
              labelText: widget.label,
              hintText: widget.hint,
              prefixIcon: widget.icon != null ? Icon(widget.icon) : null,
              suffixIcon: widget.isPassword
                  ? IconButton(
                icon: Icon(
                  _passVisible ? Icons.visibility : Icons.visibility_off,
                  color: AppColors.textVerde,
                ),
                onPressed: () => setState(() => _passVisible = !_passVisible),
              )
                  : null,
              filled: true,
              fillColor: AppColors.inputBranco,
              border: OutlineInputBorder(
                borderSide: BorderSide.none,
                borderRadius: BorderRadius.circular(15.0),
              ),
              focusedBorder: OutlineInputBorder(
                borderSide: BorderSide.none,
                borderRadius: BorderRadius.circular(15.0),
              ),
              enabledBorder: OutlineInputBorder(
                borderSide: BorderSide.none,
                borderRadius: BorderRadius.circular(15.0),
              ),
            ),
            onChanged: widget.onChanged,

            onEditingComplete: widget.onComplete,
            onTapOutside: widget.onTapOutside,
          ),

          if (widget.bottom != null) SizedBox(height: widget.bottomSpacing),

          // >>> aqui entra sua “lista de sugestões” embutida
          if (widget.bottom != null) widget.bottom!,
        ],
      ),

    );
  }
}
