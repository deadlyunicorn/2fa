import 'package:flutter/material.dart';

/// Overlay widget showing a modal spinner when asynchronous operations (e.g. KDF) are busy.
class BusyOverlay extends StatelessWidget {
  const BusyOverlay({
    required this.isBusy,
    required this.child,
    this.message,
    super.key,
  });

  final bool isBusy;
  final Widget child;
  final String? message;

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: <Widget>[
        child,
        if (isBusy)
          const ModalBarrier(dismissible: false, color: Color(0x66000000)),
        if (isBusy)
          Center(
            child: Card(
              elevation: 6,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
              ),
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 24,
                  vertical: 20,
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: <Widget>[
                    const CircularProgressIndicator(),
                    if (message != null) ...<Widget>[
                      const SizedBox(height: 16),
                      Text(
                        message!,
                        style: Theme.of(context).textTheme.bodyMedium,
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ),
      ],
    );
  }
}
