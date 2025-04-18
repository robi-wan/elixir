# SPDX-License-Identifier: Apache-2.0
# SPDX-FileCopyrightText: 2021 The Elixir Team
# SPDX-FileCopyrightText: 2012 Plataformatec

import Kernel, except: [round: 1]

defmodule Float do
  @moduledoc """
  Functions for working with floating-point numbers.

  For mathematical operations on top of floating-points,
  see Erlang's [`:math`](`:math`) module.

  ## Kernel functions

  There are functions related to floating-point numbers on the `Kernel` module
  too. Here is a list of them:

    * `Kernel.round/1`: rounds a number to the nearest integer.
    * `Kernel.trunc/1`: returns the integer part of a number.

  ## Known issues

  There are some very well known problems with floating-point numbers
  and arithmetic due to the fact most decimal fractions cannot be
  represented by a floating-point binary and most operations are not exact,
  but operate on approximations. Those issues are not specific
  to Elixir, they are a property of floating point representation itself.

  For example, the numbers 0.1 and 0.01 are two of them, what means the result
  of squaring 0.1 does not give 0.01 neither the closest representable. Here is
  what happens in this case:

    * The closest representable number to 0.1 is 0.1000000014
    * The closest representable number to 0.01 is 0.0099999997
    * Doing 0.1 * 0.1 should return 0.01, but because 0.1 is actually 0.1000000014,
      the result is 0.010000000000000002, and because this is not the closest
      representable number to 0.01, you'll get the wrong result for this operation

  There are also other known problems like flooring or rounding numbers. See
  `round/2` and `floor/2` for more details about them.

  To learn more about floating-point arithmetic visit:

    * [0.30000000000000004.com](http://0.30000000000000004.com/)
    * [What Every Programmer Should Know About Floating-Point Arithmetic](https://floating-point-gui.de/)

  """

  import Bitwise

  @power_of_2_to_52 4_503_599_627_370_496
  @precision_range 0..15
  @type precision_range :: 0..15

  @min_finite then(<<0xFFEFFFFFFFFFFFFF::64>>, fn <<num::float>> -> num end)
  @max_finite then(<<0x7FEFFFFFFFFFFFFF::64>>, fn <<num::float>> -> num end)

  @doc """
  Returns the maximum finite value for a float.

  ## Examples

      iex> Float.max_finite()
      1.7976931348623157e308

  """
  @spec max_finite() :: float
  def max_finite, do: @max_finite

  @doc """
  Returns the minimum finite value for a float.

  ## Examples

      iex> Float.min_finite()
      -1.7976931348623157e308

  """
  @spec min_finite() :: float
  def min_finite, do: @min_finite

  @doc """
  Computes `base` raised to power of `exponent`.

  `base` must be a float and `exponent` can be any number.
  However, if a negative base and a fractional exponent
  are given, it raises `ArithmeticError`.

  It always returns a float. See `Integer.pow/2` for
  exponentiation that returns integers.

  ## Examples

      iex> Float.pow(2.0, 0)
      1.0
      iex> Float.pow(2.0, 1)
      2.0
      iex> Float.pow(2.0, 10)
      1024.0
      iex> Float.pow(2.0, -1)
      0.5
      iex> Float.pow(2.0, -3)
      0.125

      iex> Float.pow(3.0, 1.5)
      5.196152422706632

      iex> Float.pow(-2.0, 3)
      -8.0
      iex> Float.pow(-2.0, 4)
      16.0

      iex> Float.pow(-1.0, 0.5)
      ** (ArithmeticError) bad argument in arithmetic expression

  """
  @doc since: "1.12.0"
  @spec pow(float, number) :: float
  def pow(base, exponent) when is_float(base) and is_number(exponent),
    do: :math.pow(base, exponent)

  @doc """
  Parses a binary into a float.

  If successful, returns a tuple in the form of `{float, remainder_of_binary}`;
  when the binary cannot be coerced into a valid float, the atom `:error` is
  returned.

  If the size of float exceeds the maximum size of `1.7976931348623157e+308`,
  `:error` is returned even though the textual representation itself might be
  well formed.

  If you want to convert a string-formatted float directly to a float,
  `String.to_float/1` can be used instead.

  ## Examples

      iex> Float.parse("34")
      {34.0, ""}
      iex> Float.parse("34.25")
      {34.25, ""}
      iex> Float.parse("56.5xyz")
      {56.5, "xyz"}

      iex> Float.parse(".12")
      :error
      iex> Float.parse("pi")
      :error
      iex> Float.parse("1.7976931348623159e+308")
      :error

  """
  @spec parse(binary) :: {float, binary} | :error
  def parse("-" <> binary) do
    case parse_unsigned(binary) do
      :error -> :error
      {number, remainder} -> {-number, remainder}
    end
  end

  def parse("+" <> binary) do
    parse_unsigned(binary)
  end

  def parse(binary) do
    parse_unsigned(binary)
  end

  defp parse_unsigned(<<digit, rest::binary>>) when digit in ?0..?9,
    do: parse_unsigned(rest, false, false, [digit])

  defp parse_unsigned(binary) when is_binary(binary), do: :error

  defp parse_unsigned(<<digit, rest::binary>>, dot?, e?, acc) when digit in ?0..?9,
    do: parse_unsigned(rest, dot?, e?, [digit | acc])

  defp parse_unsigned(<<?., digit, rest::binary>>, false, false, acc) when digit in ?0..?9,
    do: parse_unsigned(rest, true, false, [digit, ?. | acc])

  defp parse_unsigned(<<exp_marker, digit, rest::binary>>, dot?, false, acc)
       when exp_marker in ~c"eE" and digit in ?0..?9,
       do: parse_unsigned(rest, true, true, [digit, ?e | add_dot(acc, dot?)])

  defp parse_unsigned(<<exp_marker, sign, digit, rest::binary>>, dot?, false, acc)
       when exp_marker in ~c"eE" and sign in ~c"-+" and digit in ?0..?9,
       do: parse_unsigned(rest, true, true, [digit, sign, ?e | add_dot(acc, dot?)])

  # When floats are expressed in scientific notation, :erlang.binary_to_float/1 can raise an
  # ArgumentError if the e exponent is too big. For example, "1.0e400". Because of this, we
  # rescue the ArgumentError here and return an error.
  defp parse_unsigned(rest, dot?, true = _e?, acc) do
    acc
    |> add_dot(dot?)
    |> :lists.reverse()
    |> :erlang.list_to_float()
  rescue
    ArgumentError -> :error
  else
    float -> {float, rest}
  end

  defp parse_unsigned(rest, dot?, false = _e?, acc) do
    float =
      acc
      |> add_dot(dot?)
      |> :lists.reverse()
      |> :erlang.list_to_float()

    {float, rest}
  end

  defp add_dot(acc, true), do: acc
  defp add_dot(acc, false), do: [?0, ?. | acc]

  @doc """
  Rounds a float to the largest float less than or equal to `number`.

  `floor/2` also accepts a precision to round a floating-point value down
  to an arbitrary number of fractional digits (between 0 and 15).
  The operation is performed on the binary floating point, without a
  conversion to decimal.

  This function always returns a float. `Kernel.trunc/1` may be used instead to
  truncate the result to an integer afterwards.

  ## Known issues

  The behavior of `floor/2` for floats can be surprising. For example:

      iex> Float.floor(12.52, 2)
      12.51

  One may have expected it to floor to 12.52. This is not a bug.
  Most decimal fractions cannot be represented as a binary floating point
  and therefore the number above is internally represented as 12.51999999,
  which explains the behavior above.

  ## Examples

      iex> Float.floor(34.25)
      34.0
      iex> Float.floor(-56.5)
      -57.0
      iex> Float.floor(34.259, 2)
      34.25

  """
  @spec floor(float, precision_range) :: float
  def floor(number, precision \\ 0)

  def floor(number, 0) when is_float(number) do
    :math.floor(number)
  end

  def floor(number, precision) when is_float(number) and precision in @precision_range do
    round(number, precision, :floor)
  end

  def floor(number, precision) when is_float(number) do
    raise ArgumentError, invalid_precision_message(precision)
  end

  @doc """
  Rounds a float to the smallest float greater than or equal to `number`.

  `ceil/2` also accepts a precision to round a floating-point value down
  to an arbitrary number of fractional digits (between 0 and 15).

  The operation is performed on the binary floating point, without a
  conversion to decimal.

  The behavior of `ceil/2` for floats can be surprising. For example:

      iex> Float.ceil(-12.52, 2)
      -12.51

  One may have expected it to ceil to -12.52. This is not a bug.
  Most decimal fractions cannot be represented as a binary floating point
  and therefore the number above is internally represented as -12.51999999,
  which explains the behavior above.

  This function always returns floats. `Kernel.trunc/1` may be used instead to
  truncate the result to an integer afterwards.

  ## Examples

      iex> Float.ceil(34.25)
      35.0
      iex> Float.ceil(-56.5)
      -56.0
      iex> Float.ceil(34.251, 2)
      34.26
      iex> Float.ceil(-0.01)
      -0.0

  """
  @spec ceil(float, precision_range) :: float
  def ceil(number, precision \\ 0)

  def ceil(number, 0) when is_float(number) do
    :math.ceil(number)
  end

  def ceil(number, precision) when is_float(number) and precision in @precision_range do
    round(number, precision, :ceil)
  end

  def ceil(number, precision) when is_float(number) do
    raise ArgumentError, invalid_precision_message(precision)
  end

  @doc """
  Rounds a floating-point value to an arbitrary number of fractional
  digits (between 0 and 15).

  The rounding direction always ties to half up. The operation is
  performed on the binary floating point, without a conversion to decimal.

  This function only accepts floats and always returns a float. Use
  `Kernel.round/1` if you want a function that accepts both floats
  and integers and always returns an integer.

  ## Known issues

  The behavior of `round/2` for floats can be surprising. For example:

      iex> Float.round(5.5675, 3)
      5.567

  One may have expected it to round to the half up 5.568. This is not a bug.
  Most decimal fractions cannot be represented as a binary floating point
  and therefore the number above is internally represented as 5.567499999,
  which explains the behavior above. If you want exact rounding for decimals,
  you must use a decimal library. The behavior above is also in accordance
  to reference implementations, such as "Correctly Rounded Binary-Decimal and
  Decimal-Binary Conversions" by David M. Gay.

  ## Examples

      iex> Float.round(12.5)
      13.0
      iex> Float.round(5.5674, 3)
      5.567
      iex> Float.round(5.5675, 3)
      5.567
      iex> Float.round(-5.5674, 3)
      -5.567
      iex> Float.round(-5.5675)
      -6.0
      iex> Float.round(12.341444444444441, 15)
      12.341444444444441
      iex> Float.round(-0.01)
      -0.0

  """
  @spec round(float, precision_range) :: float
  # This implementation is slow since it relies on big integers.
  # Faster implementations are available on more recent papers
  # and could be implemented in the future.
  def round(float, precision \\ 0)

  def round(float, 0) when float == 0.0, do: float

  def round(float, 0) when is_float(float) do
    case float |> :erlang.round() |> :erlang.float() do
      zero when zero == 0.0 and float < 0.0 -> -0.0
      rounded -> rounded
    end
  end

  def round(float, precision) when is_float(float) and precision in @precision_range do
    round(float, precision, :half_up)
  end

  def round(float, precision) when is_float(float) do
    raise ArgumentError, invalid_precision_message(precision)
  end

  defp round(num, _precision, _rounding) when is_float(num) and num == 0.0, do: num

  defp round(float, precision, rounding) do
    <<sign::1, exp::11, significant::52-bitstring>> = <<float::float>>
    {num, count} = decompose(significant, 1)
    count = count - exp + 1023

    cond do
      # Precision beyond 15 digits
      count >= 104 ->
        case rounding do
          :ceil when sign === 0 -> 1 / power_of_10(precision)
          :floor when sign === 1 -> -1 / power_of_10(precision)
          :ceil when sign === 1 -> minus_zero()
          :half_up when sign === 1 -> minus_zero()
          _ -> 0.0
        end

      # We are asking more precision than we have
      count <= precision ->
        float

      true ->
        # Difference in precision between float and asked precision
        # We subtract 1 because we need to calculate the remainder too
        diff = count - precision - 1

        # Get up to latest so we calculate the remainder
        power_of_10 = power_of_10(diff)

        # Convert the numerand to decimal base
        num = num * power_of_5(count)

        # Move to the given precision - 1
        num = div(num, power_of_10)
        div = div(num, 10)
        num = rounding(rounding, sign, num, div)

        # Convert back to float without loss
        # https://www.exploringbinary.com/correct-decimal-to-floating-point-using-big-integers/
        den = power_of_10(precision)
        boundary = den <<< 52

        cond do
          num == 0 and sign == 1 ->
            minus_zero()

          num == 0 ->
            0.0

          num >= boundary ->
            {den, exp} = scale_down(num, boundary, 52)
            decimal_to_float(sign, num, den, exp)

          true ->
            {num, exp} = scale_up(num, boundary, 52)
            decimal_to_float(sign, num, den, exp)
        end
    end
  end

  # TODO remove once we require Erlang/OTP 27+
  # This function tricks the compiler to avoid this bug in previous versions:
  # https://github.com/elixir-lang/elixir/blob/main/lib/elixir/lib/float.ex#L408-L412
  defp minus_zero, do: -0.0

  defp decompose(significant, initial) do
    decompose(significant, 1, 0, initial)
  end

  defp decompose(<<1::1, bits::bitstring>>, count, last_count, acc) do
    decompose(bits, count + 1, count, (acc <<< (count - last_count)) + 1)
  end

  defp decompose(<<0::1, bits::bitstring>>, count, last_count, acc) do
    decompose(bits, count + 1, last_count, acc)
  end

  defp decompose(<<>>, _count, last_count, acc) do
    {acc, last_count}
  end

  defp scale_up(num, boundary, exp) when num >= boundary, do: {num, exp}
  defp scale_up(num, boundary, exp), do: scale_up(num <<< 1, boundary, exp - 1)

  defp scale_down(num, den, exp) do
    new_den = den <<< 1

    if num < new_den do
      {den >>> 52, exp}
    else
      scale_down(num, new_den, exp + 1)
    end
  end

  defp decimal_to_float(sign, num, den, exp) do
    quo = div(num, den)
    rem = num - quo * den

    tmp =
      case den >>> 1 do
        den when rem > den -> quo + 1
        den when rem < den -> quo
        _ when (quo &&& 1) === 1 -> quo + 1
        _ -> quo
      end

    tmp = tmp - @power_of_2_to_52
    <<tmp::float>> = <<sign::1, exp + 1023::11, tmp::52>>
    tmp
  end

  defp rounding(:floor, 1, _num, div), do: div + 1
  defp rounding(:ceil, 0, _num, div), do: div + 1

  defp rounding(:half_up, _sign, num, div) do
    case rem(num, 10) do
      rem when rem < 5 -> div
      rem when rem >= 5 -> div + 1
    end
  end

  defp rounding(_, _, _, div), do: div

  Enum.reduce(0..104, 1, fn x, acc ->
    defp power_of_10(unquote(x)), do: unquote(acc)
    acc * 10
  end)

  Enum.reduce(0..104, 1, fn x, acc ->
    defp power_of_5(unquote(x)), do: unquote(acc)
    acc * 5
  end)

  @doc """
  Returns a pair of integers whose ratio is exactly equal
  to the original float and with a positive denominator.

  ## Examples

      iex> Float.ratio(0.0)
      {0, 1}
      iex> Float.ratio(3.14)
      {7070651414971679, 2251799813685248}
      iex> Float.ratio(-3.14)
      {-7070651414971679, 2251799813685248}
      iex> Float.ratio(1.5)
      {3, 2}
      iex> Float.ratio(-1.5)
      {-3, 2}
      iex> Float.ratio(16.0)
      {16, 1}
      iex> Float.ratio(-16.0)
      {-16, 1}

  """
  @doc since: "1.4.0"
  @spec ratio(float) :: {integer, pos_integer}
  def ratio(float) when is_float(float) and float == 0.0, do: {0, 1}

  def ratio(float) when is_float(float) do
    <<sign::1, exp::11, mantissa::52>> = <<float::float>>

    {num, den_exp} =
      if exp != 0 do
        # Floats are expressed like this:
        # (2**52 + mantissa) * 2**(-52 + exp - 1023)
        #
        # We compute the root factors of the mantissa so we have this:
        # (2**52 + mantissa * 2**count) * 2**(-52 + exp - 1023)
        {mantissa, count} = root_factors(mantissa, 0)

        # Now we can move the count around so we have this:
        # (2**(52-count) + mantissa) * 2**(count + -52 + exp - 1023)
        if mantissa == 0 do
          {1, exp - 1023}
        else
          num = (1 <<< (52 - count)) + mantissa
          den_exp = count - 52 + exp - 1023
          {num, den_exp}
        end
      else
        # Subnormals are expressed like this:
        # (mantissa) * 2**(-52 + 1 - 1023)
        #
        # So we compute it to this:
        # (mantissa * 2**(count)) * 2**(-52 + 1 - 1023)
        #
        # Which becomes:
        # mantissa * 2**(count-1074)
        root_factors(mantissa, -1074)
      end

    if den_exp > 0 do
      {sign(sign, num <<< den_exp), 1}
    else
      {sign(sign, num), 1 <<< -den_exp}
    end
  end

  defp root_factors(mantissa, count) when mantissa != 0 and (mantissa &&& 1) == 0,
    do: root_factors(mantissa >>> 1, count + 1)

  defp root_factors(mantissa, count),
    do: {mantissa, count}

  @compile {:inline, sign: 2}
  defp sign(0, num), do: num
  defp sign(1, num), do: -num

  @doc """
  Returns a charlist which corresponds to the shortest text representation
  of the given float.

  It uses the algorithm presented in "Ryū: fast float-to-string conversion"
  in Proceedings of the SIGPLAN '2018 Conference on Programming Language
  Design and Implementation.

  For a configurable representation, use `:erlang.float_to_list/2`.

  Inlined by the compiler.

  ## Examples

      iex> Float.to_charlist(7.0)
      ~c"7.0"

  """
  @spec to_charlist(float) :: charlist
  def to_charlist(float) do
    :erlang.float_to_list(float, [:short])
  end

  @doc """
  Returns a binary which corresponds to the shortest text representation
  of the given float.

  The underlying algorithm changes depending on the Erlang/OTP version:

    * For OTP >= 24, it uses the algorithm presented in "Ryū: fast
      float-to-string conversion" in Proceedings of the SIGPLAN '2018
      Conference on Programming Language Design and Implementation.

    * For OTP < 24, it uses the algorithm presented in "Printing Floating-Point
      Numbers Quickly and Accurately" in Proceedings of the SIGPLAN '1996
      Conference on Programming Language Design and Implementation.

  For a configurable representation, use `:erlang.float_to_binary/2`.

  Inlined by the compiler.

  ## Examples

      iex> Float.to_string(7.0)
      "7.0"

  """
  @spec to_string(float) :: String.t()
  def to_string(float) do
    :erlang.float_to_binary(float, [:short])
  end

  @doc false
  @deprecated "Use Float.to_charlist/1 instead"
  def to_char_list(float), do: Float.to_charlist(float)

  @doc false
  @deprecated "Use :erlang.float_to_list/2 instead"
  def to_char_list(float, options) do
    :erlang.float_to_list(float, expand_compact(options))
  end

  @doc false
  @deprecated "Use :erlang.float_to_binary/2 instead"
  def to_string(float, options) do
    :erlang.float_to_binary(float, expand_compact(options))
  end

  defp invalid_precision_message(precision) do
    "precision #{precision} is out of valid range of #{inspect(@precision_range)}"
  end

  defp expand_compact([{:compact, false} | t]), do: expand_compact(t)
  defp expand_compact([{:compact, true} | t]), do: [:compact | expand_compact(t)]
  defp expand_compact([h | t]), do: [h | expand_compact(t)]
  defp expand_compact([]), do: []
end
