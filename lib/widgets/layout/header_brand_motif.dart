import 'package:flutter/material.dart';

import '../../core/theme/app_colors.dart';

class HeaderBrandMotif extends StatelessWidget {
  const HeaderBrandMotif({super.key});

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: SizedBox(
        height: 125,
        child: Stack(
          clipBehavior: Clip.none,
          children: [
            Positioned(
              right: -20,
              top: -60,
              child: Container(
                width: 250,
                height: 150,
                decoration: BoxDecoration(
                  color: AppColors.primary.withValues(alpha: .045),
                  shape: BoxShape.circle,
                ),
              ),
            ),
            Positioned(
              right: -75,
              top: -38,
              child: Transform.rotate(
                angle: -.18,
                child: Container(
                  width: 220,
                  height: 135,
                  decoration: BoxDecoration(
                    color: AppColors.orange.withValues(alpha: .07),
                    borderRadius: BorderRadius.circular(36),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
