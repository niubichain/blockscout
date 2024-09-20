defmodule Explorer.Chain.Scroll.Reader do
  @moduledoc "Contains read functions for Scroll modules."

  import Ecto.Query,
    only: [
      from: 2,
      limit: 2
    ]

  import Explorer.Chain, only: [select_repo: 1]

  alias Explorer.Chain.Scroll.{Batch, BatchBundle, Bridge}
  alias Explorer.{Chain, PagingOptions, Repo}

  @doc """
    Gets last known L1 batch item from the `scroll_batches` table.
    Returns block number and L1 transaction hash bound to that batch.
    If not found, returns zero block number and nil as the transaction hash.
  """
  @spec last_l1_batch_item() :: {non_neg_integer(), binary() | nil}
  def last_l1_batch_item do
    query =
      from(b in Batch,
        select: {b.commit_block_number, b.commit_transaction_hash},
        order_by: [desc: b.number],
        limit: 1
      )

    query
    |> Repo.one()
    |> Kernel.||({0, nil})
  end

  @doc """
    Gets `final_batch_number` from the last known L1 bundle.
    If not found, returns -1.
  """
  @spec last_final_batch_number() :: integer()
  def last_final_batch_number do
    query =
      from(bb in BatchBundle,
        select: bb.final_batch_number,
        order_by: [desc: bb.id],
        limit: 1
      )

    query
    |> Repo.one()
    |> Kernel.||(-1)
  end

  @doc """
    Gets last known L1 bridge item (deposit) from the `scroll_bridge` table.
    Returns block number and L1 transaction hash bound to that deposit.
    If not found, returns zero block number and nil as the transaction hash.
  """
  @spec last_l1_bridge_item() :: {non_neg_integer(), binary() | nil}
  def last_l1_bridge_item do
    query =
      from(b in Bridge,
        select: {b.block_number, b.l1_transaction_hash},
        where: b.type == :deposit and not is_nil(b.block_number),
        order_by: [desc: b.index],
        limit: 1
      )

    query
    |> Repo.one()
    |> Kernel.||({0, nil})
  end

  @doc """
    Gets last known L2 bridge item (withdrawal) from the `scroll_bridge` table.
    Returns block number and L2 transaction hash bound to that withdrawal.
    If not found, returns zero block number and nil as the transaction hash.
  """
  @spec last_l2_bridge_item() :: {non_neg_integer(), binary() | nil}
  def last_l2_bridge_item do
    query =
      from(b in Bridge,
        select: {b.block_number, b.l2_transaction_hash},
        where: b.type == :withdrawal and not is_nil(b.block_number),
        order_by: [desc: b.index],
        limit: 1
      )

    query
    |> Repo.one()
    |> Kernel.||({0, nil})
  end

  @doc """
    Retrieves a list of Scroll deposits (both completed and unclaimed)
    sorted in descending order of the index.

    ## Parameters
    - `options`: A keyword list of options that may include whether to use a replica database.

    ## Returns
    - A list of deposits.
  """
  @spec deposits(list()) :: list()
  def deposits(options \\ []) do
    paging_options = Keyword.get(options, :paging_options, Chain.default_paging_options())

    case paging_options do
      %PagingOptions{key: {0}} ->
        []

      _ ->
        base_query =
          from(
            b in Bridge,
            where: b.type == :deposit and not is_nil(b.l1_transaction_hash),
            order_by: [desc: b.index]
          )

        base_query
        |> page_deposits_or_withdrawals(paging_options)
        |> limit(^paging_options.page_size)
        |> select_repo(options).all()
    end
  end

  @doc """
    Returns a total number of Scroll deposits (both completed and unclaimed).
  """
  @spec deposits_count(list()) :: term() | nil
  def deposits_count(options \\ []) do
    query =
      from(
        b in Bridge,
        where: b.type == :deposit and not is_nil(b.l1_transaction_hash)
      )

    select_repo(options).aggregate(query, :count, timeout: :infinity)
  end

  @doc """
    Retrieves a list of Scroll withdrawals (both completed and unclaimed)
    sorted in descending order of the index.

    ## Parameters
    - `options`: A keyword list of options that may include whether to use a replica database.

    ## Returns
    - A list of withdrawals.
  """
  @spec withdrawals(list()) :: list()
  def withdrawals(options \\ []) do
    paging_options = Keyword.get(options, :paging_options, Chain.default_paging_options())

    case paging_options do
      %PagingOptions{key: {0}} ->
        []

      _ ->
        base_query =
          from(
            b in Bridge,
            where: b.type == :withdrawal and not is_nil(b.l2_transaction_hash),
            order_by: [desc: b.index]
          )

        base_query
        |> page_deposits_or_withdrawals(paging_options)
        |> limit(^paging_options.page_size)
        |> select_repo(options).all()
    end
  end

  @doc """
    Returns a total number of Scroll withdrawals (both completed and unclaimed).
  """
  @spec withdrawals_count(list()) :: term() | nil
  def withdrawals_count(options \\ []) do
    query =
      from(
        b in Bridge,
        where: b.type == :withdrawal and not is_nil(b.l2_transaction_hash)
      )

    select_repo(options).aggregate(query, :count, timeout: :infinity)
  end

  defp page_deposits_or_withdrawals(query, %PagingOptions{key: nil}), do: query

  defp page_deposits_or_withdrawals(query, %PagingOptions{key: {index}}) do
    from(b in query, where: b.index < ^index)
  end
end
