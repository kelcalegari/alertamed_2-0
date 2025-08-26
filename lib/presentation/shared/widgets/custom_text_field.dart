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
  final TimeOfDay? initialTime;

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
    this.onTapOutside, this.initialTime,
  });

  @override
  State<CustomTextField> createState() => _CustomTextFieldState();
}

class _CustomTextFieldState extends State<CustomTextField> {
  bool _passVisible = false;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.symmetric(horizontal: widget.pad),
      child: TextFormField(
        focusNode: widget.focusNode,
        controller: widget.ctrl,
        keyboardType: widget.textInputType,
        textCapitalization: widget.isPassword ? TextCapitalization.none : TextCapitalization.sentences,
        maxLength: widget.maxLength > 0 ? widget.maxLength : null,
        maxLines: widget.maxLines,
        obscureText: widget.isPassword && !_passVisible,
        validator: widget.validador,
        style: TextStyle(fontSize: widget.fontSize, color: AppColors.textVerde),
        readOnly: widget.textInputType == TextInputType.datetime || widget.isTime,
        onTap: (widget.textInputType == TextInputType.datetime || widget.isTime)
            ? () async {
          if (widget.textInputType == TextInputType.datetime) {
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

            DateTime? picked = await showDatePicker(
              context: context,
              initialDate: initialDate,
              firstDate: DateTime(1900),
              lastDate: DateTime(2100),
            );
            if (picked != null) {
              widget.ctrl.text = "${picked.day.toString().padLeft(2, '0')}/"
                  "${picked.month.toString().padLeft(2, '0')}/"
                  "${picked.year}";
            }
          } else if (widget.isTime) {
            TimeOfDay? picked = await showTimePicker(
              context: context,
              initialTime: widget.initialTime?? TimeOfDay.now(),
            );
            if (picked != null) {
              widget.ctrl.text = picked.format(context);
            }
          }
        }
            : null,
        decoration: InputDecoration(
          isDense: true, // deixa mais compacto
          contentPadding: const EdgeInsets.symmetric(
            vertical: 15, // altura interna
            horizontal: 8, // distância lateral
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

        onEditingComplete: widget.onComplete,
        onTapOutside: widget.onTapOutside,
      ),
    );
  }
}
