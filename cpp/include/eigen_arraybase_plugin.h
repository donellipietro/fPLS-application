// Eigen 3.4.1's expression overload captures integer literals before scalar conversion.
template <typename T = Scalar>
EIGEN_DEVICE_FUNC EIGEN_STRONG_INLINE auto max(int other) const
    requires(!std::is_same_v<T, int>) {
  return (max)(static_cast<Scalar>(other));
}
