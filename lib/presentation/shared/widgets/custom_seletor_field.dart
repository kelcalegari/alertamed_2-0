import 'package:flutter/material.dart';
import '../../themes/app_colors.dart';

class CustomSelectorField<T> extends StatelessWidget {
  final T? selectedValue;
  final List<DropdownMenuItem<T>> items;
  final void Function(T?) onChanged;

  final String? label;
  final String? hint;
  final IconData? icon;
  final double pad;
  final double fontSize;
  final String? Function(T?)? validador;
  final FocusNode? focusNode;
  final void Function()? onComplete;

  /// Novo: modo somente leitura
  final bool locked;

  /// Cores personalizáveis
  final Color backgroundColor; // cor do campo fechado
  final Color textColor;       // cor do texto/ícone
  final Color? dropdownColor;  // cor da lista aberta

  const CustomSelectorField({
    super.key,
    required this.selectedValue,
    required this.items,
    required this.onChanged,
    this.label,
    this.hint,
    this.icon,
    this.pad = 20,
    this.fontSize = 20,
    this.validador,
    this.focusNode,
    this.onComplete,
    this.locked = false,
    this.backgroundColor = AppColors.inputBranco,
    this.textColor = AppColors.textVerde,
    this.dropdownColor, // novo
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.symmetric(horizontal: pad),
      child: Theme(
        data: Theme.of(context).copyWith(
          canvasColor: dropdownColor ?? backgroundColor, // aplica no menu
          cardTheme: CardTheme(
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(15.0),
            ),
          ),
        ),
        child: DropdownButtonHideUnderline(
          child: DropdownButtonFormField<T>(
            isExpanded: true,
            focusNode: focusNode,
            value: selectedValue,
            items: items,
            onChanged: locked ? null : onChanged,
            onTap: locked ? null : onComplete,
            validator: validador,
            dropdownColor: dropdownColor ?? backgroundColor, // cor do menu suspenso
            icon: locked
                ? const SizedBox.shrink()
                : Icon(Icons.arrow_drop_down, color: textColor),
            style: TextStyle(
              fontSize: fontSize,
              color: textColor,
            ),
            decoration: InputDecoration(
              labelText: label,
              labelStyle: TextStyle(color: textColor),
              hintText: hint,
              hintStyle: TextStyle(color: textColor.withOpacity(0.6)),
              prefixIcon: icon != null ? Icon(icon, color: textColor) : null,
              filled: true,
              fillColor: backgroundColor,
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
          ),
        ),
      ),
    );
  }
}
