import 'package:chipkizi/views/my_progress_indicator.dart';
import 'package:flutter/material.dart';

class ProgressButton extends StatelessWidget {
  /// the [indicator] can be any widget but is typically a [MyProgressIndicator]
  /// for example a [Builder] that eventually returns a [MyProgressIndicator]
  final Widget indicator;
  final double size;
  /// typically an [IconButton] but can be assigned to another fitting widget 
  /// like an [Icon], a [CircleAvatar] or a [Text] widget
  final Widget button;
  final Color color;

  const ProgressButton(
      {Key key,
     this.indicator,
      @required this.size,
      @required this.button,
      @required this.color})
      : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: <Widget>[
        Positioned(
          top: 0.0,
          bottom: 0.0,
          left: 0.0,
          right: 0.0,
          child: indicator,
        ), 
        indicator != null 
        ?
        Material(
          shape: CircleBorder(),
          color: color,
          elevation: 4.0,
          child: Container(
            height: size,
            width: size,
            decoration: BoxDecoration(shape: BoxShape.circle),
            child: button,
          ),
        ):
        Container(),
      ],
    );
  }
}
