float first_order_iir(float x) {
  static float old_x = 0.0f;
  static float alpha = 0.9f; // 5*T = -5/ln(0.9) = 47.5 Samples settling time.

  x = x * (1.0f - alpha) + old_x * alpha;
  return x;
}
