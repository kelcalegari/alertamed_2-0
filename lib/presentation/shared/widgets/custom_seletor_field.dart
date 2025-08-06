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
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.symmetric(horizontal: pad),
      child: Theme(
        data: Theme.of(context).copyWith(
          canvasColor: AppColors.inputBranco,
          cardTheme: CardTheme(
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(15.0), // borda do menu
            ),
          ),
        ),
        child: DropdownButtonFormField<T>(
          focusNode: focusNode,
          value: selectedValue,
          items: items,
          onChanged: onChanged,
          validator: validador,
          style: TextStyle(
            fontSize: fontSize,
            color: AppColors.textVerde,
          ),
          decoration: InputDecoration(
            labelText: label,
            hintText: hint,
            prefixIcon: icon != null ? Icon(icon,color: AppColors.textVerde,) : null,
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
          onTap: onComplete,
        ),
      ),
    );
  }
}
