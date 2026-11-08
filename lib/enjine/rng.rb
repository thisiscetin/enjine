# frozen_string_literal: true

module Enjine
  # PCG32 (XSH-RR) random number generator.
  #
  # The whole generator state is one 64-bit Integer, so it serializes into a
  # snapshot as a plain number and replays identically on every platform.
  class Rng
    MULTIPLIER = 6_364_136_223_846_793_005
    INCREMENT = 1_442_695_040_888_963_407
    MASK64 = (1 << 64) - 1
    MASK32 = (1 << 32) - 1
    RANGE32 = 1 << 32

    attr_reader :state

    def self.from_seed(seed)
      rng = new(0)
      rng.next_u32
      rng.instance_variable_set(:@state, (rng.state + (Integer(seed) & MASK64)) & MASK64)
      rng.next_u32
      rng
    end

    def initialize(state)
      @state = Integer(state) & MASK64
    end

    def next_u32
      old = @state
      @state = ((old * MULTIPLIER) + INCREMENT) & MASK64
      xorshifted = (((old >> 18) ^ old) >> 27) & MASK32
      rot = old >> 59
      ((xorshifted >> rot) | (xorshifted << ((-rot) & 31))) & MASK32
    end

    # Unbiased integer in 0...n (Lemire-free rejection sampling).
    def rand(bound)
      raise ArgumentError, "bound must be in 1..2**32" unless bound.is_a?(Integer) && bound.positive? && bound <= RANGE32

      threshold = (RANGE32 - bound) % bound
      loop do
        r = next_u32
        return r % bound if r >= threshold
      end
    end

    # In-place Fisher-Yates shuffle.
    def shuffle!(array)
      (array.size - 1).downto(1) do |i|
        j = rand(i + 1)
        array[i], array[j] = array[j], array[i]
      end
      array
    end
  end
end
