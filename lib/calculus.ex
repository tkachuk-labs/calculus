defmodule Calculus do
  @moduledoc """
  Proof of concept inspired by church encoding.

  Example of "Calculus" data type `User` have:

  - mutable `name` field (`get_name/1`, `set_name/2` methods)
  - immutable `id` field (`get_id/1` method)
  - private `balance` field (used internally in `deposit/2` and `withdraw/2` methods)

  ## Example

  ```
  iex> it0 = User.new(id: 1, name: "Jessy")
  iex> 1 = User.get_id(it0)
  iex> "Jessy" = User.get_name(it0)
  iex> it1 = User.set_name(it0, "Bob")
  iex> "Jessy" = User.return(it1)
  iex> "Bob" = User.get_name(it1)
  iex> it2 = User.deposit(it1, 100)
  iex> :ok = User.return(it2)
  iex> it3 = User.withdraw(it2, 50)
  iex> :ok = User.return(it3)
  iex> it4 = User.withdraw(it3, 51)
  iex> :insufficient_funds = User.return(it4)
  iex> Enum.all?([it0, it1, it2, it3, it4], &is_function/1)
  iex> true
  true

  iex> User.new(id: 1, name: "Jessy") |> User.deposit(100) |> User.set_name("Bob") |> User.withdraw(50) |> User.get_name
  "Bob"

  iex> it = User.new(id: 1, name: "Jessy")
  iex> it.(:get_name, :fake_security_key)
  ** (RuntimeError) For instance of the type Elixir.Calculus got unsupported CMD=:get_name with SECURITY_KEY=:fake_security_key

  iex> User.get_name(&({&2, &1}))
  ** (RuntimeError) Instance of the type Elixir.User can't be created in other module Elixir.CalculusTest
  ```
  """

  defmacro __using__(_) do
    quote location: :keep do
      import Calculus, only: [defcalculus: 2]
    end
  end

  defp add_security_key({:-> = exp, ctx, [left, right]}) do
    key = {
      :@,
      [context: Elixir, import: Kernel],
      [{:security_key, [context: Elixir], Elixir}]
    }

    new_left =
      case left do
        [{:when, ctx0, [e | es]}] -> [{:when, ctx0, [e, key | es]}]
        [e] -> [e, key]
      end

    {exp, ctx, [new_left, right]}
  end

  defmacro defcalculus(quoted_it, do: raw_eval_clauses) do
    default_eval_clause =
      quote location: :keep do
        cmd, security_key ->
          raise(
            "For instance of the type #{__MODULE__} got unsupported CMD=#{inspect(cmd)} with SECURITY_KEY=#{
              inspect(security_key)
            }"
          )
      end

    eval_clauses =
      raw_eval_clauses
      |> case do
        {:__block__, _, []} -> []
        [_ | _] -> raw_eval_clauses
      end
      |> Enum.map(&add_security_key/1)
      |> Enum.concat(default_eval_clause)

    eval_fn = {:fn, [], eval_clauses}

    quote location: :keep do
      @security_key 64 |> :crypto.strong_rand_bytes() |> Base.encode64() |> String.to_atom()

      defmacrop calculus(state: state, return: return) do
        quote location: :keep do
          Calculus.new(unquote(state), unquote(return))
        end
      end

      defmacrop calculus(return: return, state: state) do
        quote location: :keep do
          Calculus.new(unquote(state), unquote(return))
        end
      end

      defmacrop calculus(some) do
        "Calculus expect keyword list, example: calculus(state: foo, return: bar). But got term #{
          inspect(some)
        }"
        |> raise
      end

      defp eval(fx, cmd) do
        case Function.info(fx, :module) do
          {:module, __MODULE__} ->
            cs = fx.(cmd, @security_key)
            unquote(quoted_it) = Calculus.it(cs)
            Calculus.new(unquote(eval_fn), Calculus.returns(cs))

          {:module, unquote(__MODULE__)} ->
            fx
            |> unquote(__MODULE__).it()
            |> eval(cmd)

          {:module, module} ->
            "Instance of the type #{__MODULE__} can't be created in other module #{module}"
            |> raise
        end
      end

      def return(fx) do
        Calculus.returns(fx)
      end

      defmacrop construct(x) do
        quote location: :keep do
          fn :new, @security_key ->
            Calculus.new(unquote(x), :ok)
          end
          |> eval(:new)
        end
      end
    end
  end

  #
  # define calculus data type as church-encoded type as well
  #

  require Record

  Record.defrecordp(:calculus,
    it: nil,
    returns: nil
  )

  @security_key 64 |> :crypto.strong_rand_bytes() |> Base.encode64() |> String.to_atom()

  defp eval(f0, cmd) do
    case Function.info(f0, :module) do
      {:module, __MODULE__} ->
        calculus(
          it: calculus(it: it1, returns: returns1) = it0,
          returns: returns0
        ) = f0.(cmd, @security_key)

        f1 = fn
          :it, @security_key ->
            calculus(it: it0, returns: it1)

          :returns, @security_key ->
            calculus(it: it0, returns: returns1)

          cmd, security_key ->
            raise(
              "For instance of the type #{__MODULE__} got unsupported CMD=#{inspect(cmd)} with SECURITY_KEY=#{
                inspect(security_key)
              }"
            )
        end

        calculus(it: f1, returns: returns0)

      {:module, module} ->
        "Instance of the type #{__MODULE__} can't be created in other module #{module}"
        |> raise
    end
  end

  def new(it0, returns0) do
    calculus(it: it1, returns: :ok) =
      fn
        :new, @security_key ->
          calculus(
            it: calculus(it: it0, returns: returns0),
            returns: :ok
          )
      end
      |> eval(:new)

    it1
  end

  def it(fx) do
    calculus(it: ^fx, returns: it) = eval(fx, :it)
    it
  end

  def returns(fx) do
    calculus(it: ^fx, returns: returns) = eval(fx, :returns)
    returns
  end
end
