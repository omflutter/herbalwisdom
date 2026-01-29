import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

class OtpFields extends StatefulWidget {
  final int length;
  final void Function(String code)? onChanged;
  final void Function(String code)? onCompleted;

  const OtpFields({super.key, this.length = 6, this.onChanged, this.onCompleted});

  @override
  State<OtpFields> createState() => _OtpFieldsState();
}

class _OtpFieldsState extends State<OtpFields> {
  late final List<TextEditingController> _ctrls;
  late final List<FocusNode> _nodes;

  @override
  void initState() {
    super.initState();
    _ctrls = List.generate(widget.length, (_) => TextEditingController());
    _nodes = List.generate(widget.length, (_) => FocusNode());
  }

  @override
  void dispose() {
    for (final c in _ctrls) c.dispose();
    for (final n in _nodes) n.dispose();
    super.dispose();
  }

  void _emit() {
    final code = _ctrls.map((c) => c.text).join();
    widget.onChanged?.call(code);
    if (code.length == widget.length) widget.onCompleted?.call(code);
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(builder: (context, box) {
      final totalWidth = box.maxWidth;
      // compute a width that fits even on small screens
      final w = (totalWidth - (widget.length - 1) * 10) / widget.length;
      final cellW = w.clamp(40, 54).toDouble();

      return Wrap(
        alignment: WrapAlignment.center,
        spacing: 10,
        runSpacing: 10,
        children: List.generate(widget.length, (i) {
          return SizedBox(
            width: cellW,
            child: TextField(
              controller: _ctrls[i],
              focusNode: _nodes[i],
              textAlign: TextAlign.center,
              keyboardType: TextInputType.number,
              inputFormatters: [FilteringTextInputFormatter.digitsOnly],
              maxLength: 1,
              decoration: const InputDecoration(
                counterText: '',
                border: OutlineInputBorder(),
              ),
              onChanged: (v) {
                if (v.isNotEmpty && i < widget.length - 1) {
                  _nodes[i + 1].requestFocus();
                } else if (v.isEmpty && i > 0) {
                  _nodes[i - 1].requestFocus();
                }
                _emit();
              },
            ),
          );
        }),
      );
    });
  }
}
