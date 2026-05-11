import 'package:flutter/material.dart';
import 'package:flutter/physics.dart';

/// Scroll physics that mimic WhatsApp's chat list feel:
/// - Fast response to touch (low drag friction while finger is down)
/// - Long, slow deceleration after fling (high momentum retention)
/// - Hard clamp at boundaries — no bounce
class ChatScrollPhysics extends ScrollPhysics {
  const ChatScrollPhysics({super.parent});

  @override
  ChatScrollPhysics applyTo(ScrollPhysics? ancestor) {
    return ChatScrollPhysics(parent: buildParent(ancestor));
  }

  // ── Friction ──────────────────────────────────────────────────────────────
  // Flutter default is 0.015. Lower = less drag = longer glide.
  // WhatsApp-like feel sits around 0.010–0.012.
  @override
  double get minFlingVelocity => 50.0;

  @override
  double get maxFlingVelocity => 9000.0;

  @override
  double get dragStartDistanceMotionThreshold => 3.5;

  // Keep momentum between repeated flings so quick successive swipes feel heavier.
  @override
  double carriedMomentum(double existingVelocity) {
    final base = super.carriedMomentum(existingVelocity);
    return base.clamp(-1600.0, 1600.0);
  }

  @override
  Simulation? createBallisticSimulation(
    ScrollMetrics position,
    double velocity,
  ) {
    final tolerance = toleranceFor(position);

    // Already at rest or negligible velocity — stop immediately.
    if (velocity.abs() < tolerance.velocity) return null;

    // Hard-clamp at boundaries (no bounce).
    if (velocity > 0 && position.pixels >= position.maxScrollExtent) {
      return null;
    }
    if (velocity < 0 && position.pixels <= position.minScrollExtent) {
      return null;
    }

    // ClampingScrollSimulation with a lower friction coefficient gives the
    // long, smooth deceleration tail that WhatsApp is known for.
    return ClampingScrollSimulation(
      position: position.pixels,
      velocity: velocity,
      // Default friction is 0.015. We use 0.010 for a ~50 % longer glide.
      friction: 0.010,
      tolerance: tolerance,
    );
  }

  // Keep over-scroll disabled (clamp, not bounce).
  @override
  double applyBoundaryConditions(ScrollMetrics position, double value) {
    if (value < position.pixels &&
        position.pixels <= position.minScrollExtent) {
      return value - position.pixels;
    }
    if (position.maxScrollExtent <= position.pixels &&
        position.pixels < value) {
      return value - position.pixels;
    }
    if (value < position.minScrollExtent &&
        position.minScrollExtent < position.pixels) {
      return value - position.minScrollExtent;
    }
    if (position.pixels < position.maxScrollExtent &&
        position.maxScrollExtent < value) {
      return value - position.maxScrollExtent;
    }
    return 0.0;
  }

  @override
  bool get allowImplicitScrolling => false;
}
