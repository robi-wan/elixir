defmodule Mix.Tasks.Profile.Eprof do
  use Mix.Task

  @shortdoc "Profiles the given file or expression with eprof"

  @moduledoc """
  Profiles the given file or expression using Erlang's `eprof` tool.

  `:eprof` provides time information of each function call and can be useful
  when you want to discover the bottlenecks related to this.

  Before running the code, it invokes the `app.start` task which compiles
  and loads your project. Then the target expression is profiled, together
  with all matching function calls using the Erlang trace BIFs. The tracing of
  the function calls for that is enabled when the profiling is begun, and
  disabled when profiling is stopped.

  To profile the code, you can use syntax similar to the `mix run` task:

      mix profile.eprof -e Hello.world
      mix profile.eprof -e "[1, 2, 3] |> Enum.reverse |> Enum.map(&Integer.to_string/1)"
      mix profile.eprof my_script.exs arg1 arg2 arg3

  ## Command line options

    * `--matching` - only profile calls matching the given `Module.function/arity` pattern
    * `--calls` - filters out any results with a call count lower than this
    * `--time` - filters out any results that took lower than specified (in µs)
    * `--sort` - sort the results by `time` or `calls` (default: `time`)
    * `--config`, `-c` - loads the given configuration file
    * `--eval`, `-e` - evaluate the given code
    * `--require`, `-r` - requires pattern before running the command
    * `--parallel`, `-p` - makes all requires parallel
    * `--no-warmup` - skip the warmup step before profiling
    * `--no-compile` - does not compile even if files require compilation
    * `--no-deps-check` - does not check dependencies
    * `--no-archives-check` - does not check archives
    * `--no-halt` - does not halt the system after running the command
    * `--no-start` - does not start applications after compilation
    * `--no-elixir-version-check` - does not check the Elixir version from mix.exs

  ## Profile output

  Example output:

      #                                               CALLS     % TIME µS/CALL
      Total                                              24 100.0   26    1.08
      Enum.reduce_range_inc/4                             5  3.85    1    0.20
      :erlang.make_fun/3                                  1  7.69    2    2.00
      Enum.each/2                                         1  7.69    2    2.00
      anonymous fn/0 in :elixir_compiler_0.__FILE__/1     1  7.69    2    2.00
      :erlang.integer_to_binary/1                         5 15.39    4    0.80
      :erlang.apply/2                                     1 15.39    4    4.00
      anonymous fn/3 in Enum.each/2                       5 19.23    5    1.00
      String.Chars.Integer.to_string/1                    5 23.08    6    1.20

      Profile done over 8 matching functions

  The default output contains data gathered from all matching functions. The first
  row after the header contains the sums of the partial results and the average time
  for all the function calls listed. The following rows contain the function call,
  followed by the number of times that the function was called, then by the percentage
  of time that the call uses, then the total time for that function in microseconds,
  and, finally, the average time per call in microseconds.

  When `--matching` option is specified, call count tracing will be started only for
  the functions matching the given pattern:

      #                                               CALLS     % TIME µS/CALL
      Total                                               5 100.0    6    1.20
      String.Chars.Integer.to_string/1                    5 100.0    6    1.20

      Profile done over 1 matching functions

  The pattern can be a module name, such as `String` to count all calls to that module,
  a call without arity, such as `String.split`, to count all calls to that function
  regardless of arity, or a call with arity, such as `String.split/2`, to count all
  calls to that exact module, function and arity.

  ## Caveats

  You should be aware that the code being profiled is running in an anonymous
  function which is invoked by [`:eprof` module](http://wwww.erlang.org/doc/man/eprof.html).
  Thus, you'll see some additional entries in your profile output. It is also
  important to notice that the profiler is stopped as soon as the code has finished running,
  and this may need special attention, when: running asynchronous code as function calls which were
  called before the profiler stopped will not be counted; running synchronous code as long
  running computations and a profiler without a proper MFA trace pattern or filter may
  lead to a result set which is difficult to comprehend.

  You should expect a slowdown in your code execution using this tool since `:eprof` has
  some performance impact on the execution, but the impact is considerably lower than
  `Mix.Tasks.Profile.Fprof`. If you have a large system try to profile a limited
  scenario or focus on the main modules or processes. Another alternative is to use
  `Mix.Tasks.Profile.Cprof` that uses `:cprof` and has a low performance degradation effect.
  """

  @switches [parallel: :boolean, require: :keep, eval: :keep, config: :keep, matching: :string,
             halt: :boolean, compile: :boolean, deps_check: :boolean, calls: :integer,
             time: :integer, sort: :string, start: :boolean, archives_check: :boolean,
             warmup: :boolean, elixir_version_check: :boolean, parallel_require: :keep]

  @spec run(OptionParser.argv) :: :ok
  def run(args) do
    {opts, head} =
      OptionParser.parse_head!(args,
        aliases: [r: :require, p: :parallel, e: :eval, c: :config],
        strict: @switches)

    Mix.Tasks.Run.run(["--no-mix-exs" | args], opts, head,
                      &profile_code(&1, opts),
                      &profile_code(File.read!(&1), opts))
  end

  defp profile_code(code_string, opts) do
    content =
      quote do
        unquote(__MODULE__).profile(fn ->
          unquote(Code.string_to_quoted!(code_string))
        end, unquote(opts))
      end
    # Use compile_quoted since it leaves less noise than eval_quoted
    Code.compile_quoted(content)
  end

  @doc false
  def profile(fun, opts) do
    fun
    |> profile_and_analyse(opts)
    |> print_output
  end

  defp profile_and_analyse(fun, opts) do
    if Keyword.get(opts, :warmup, true) do
      IO.puts "Warmup...\n"
      fun.()
    end

    :eprof.start()
    :eprof.profile([], fun, matching_pattern(opts))

    results =
      :eprof.dump()
      |> extract_results
      |> filter_results(opts)
      |> sort_results(opts)
      |> add_totals

    :eprof.stop()

    results
  end

  defp matching_pattern(opts) do
    case Keyword.get(opts, :matching) do
      nil ->
        {:_, :_, :_}
      matching ->
        case Mix.Utils.parse_mfa(matching) do
          {:ok, [m, f, a]} -> {m, f, a}
          {:ok, [m, f]} -> {m, f, :_}
          {:ok, [m]} -> {m, :_, :_}
          :error -> Mix.raise "Invalid matching pattern: #{matching}"
        end
    end
  end

  defp extract_results([]), do: []
  defp extract_results([{_pid, call_results}]), do: call_results

  defp filter_results(call_results, opts) do
    calls_opt = Keyword.get(opts, :calls, 0)
    time_opt = Keyword.get(opts, :time, 0)

    call_results
    |> Stream.filter(fn {_mfa, {count, _time}} -> count >= calls_opt end)
    |> Stream.filter(fn {_mfa, {_count, time}} -> time >= time_opt end)
  end

  defp sort_results(call_results, opts) do
    sort_by =
      Keyword.get(opts, :sort, "time")
      |> String.to_existing_atom
      |> sort_function

    Enum.sort_by(call_results, sort_by)
  end

  defp sort_function(:time), do: fn {_mfa, {_count, time}} -> time end
  defp sort_function(:calls), do: fn {_mfa, {count, _time}} -> count end

  defp add_totals(call_results) do
    {function_count, call_count, total_time} =
      Enum.reduce(call_results, {0, 0, 0}, fn({_, {count, time}}, {function_count, call_count, total_time}) ->
        {function_count + 1, call_count + count, total_time + time}
      end)

    {function_count, call_results, call_count, total_time}
  end

  @header ["#", "CALLS", "%", "TIME", "µS/CALL"]

  defp print_output({0, _, _, _}), do: print_function_count(0)

  defp print_output({function_count, call_results, call_count, total_time}) do
    formatted_rows = Enum.map(call_results, &(format_row(&1, total_time)))
    formatted_total = format_total(total_time, call_count)

    column_lengths = column_lengths(@header, formatted_rows)

    print_row(@header, column_lengths)
    print_row(formatted_total, column_lengths)
    Enum.each(formatted_rows, &(print_row(&1, column_lengths)))

    IO.puts ""

    print_function_count(function_count)
  end

  defp format_row({{module, function, arity}, {count, time}}, total_time) do
    mfa = Exception.format_mfa(module, function, arity)
    time_percentage = :erlang.float_to_binary(100 * time / total_time, [{:decimals, 2}])
    time_per_call = :erlang.float_to_binary(time / count, [{:decimals, 2}])
    count = Integer.to_string(count)
    time = Integer.to_string(time)

    [mfa, count, time_percentage, time, time_per_call]
  end

  defp format_total(total_time, total_count) do
    time_per_call = :erlang.float_to_binary(total_time / total_count, [{:decimals, 2}])

    ["Total", Integer.to_string(total_count), "100.00", Integer.to_string(total_time), time_per_call]
  end

  defp column_lengths(header, rows) do
    max_lengths = Enum.map(header, &String.length/1)

    Enum.reduce(rows, max_lengths, fn(row, max_lengths) ->
      Stream.map(row, &String.length/1)
      |> Stream.zip(max_lengths)
      |> Enum.map(&max/1)
    end)
  end

  defp max({a, b}) when a >= b, do: a
  defp max({_, b}), do: b

  @format "~-*s ~*s ~*s ~*s ~*s~n"

  defp print_row(row, column_lengths) do
    to_print =
      column_lengths
      |> Stream.zip(Stream.map(row, &String.to_charlist/1))
      |> Enum.flat_map(&Tuple.to_list/1)

    :io.format(@format, to_print)
  end

  def print_function_count(count) do
    IO.puts "Profile done over #{count} matching functions"
  end
end
