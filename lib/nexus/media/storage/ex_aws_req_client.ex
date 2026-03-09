defmodule Nexus.Media.Storage.ExAwsReqClient do
  @moduledoc """
  ExAws HTTP client adapter using Req instead of hackney.
  """

  @behaviour ExAws.Request.HttpClient

  @impl true
  def request(method, url, body, headers, http_opts \\ []) do
    timeout = Keyword.get(http_opts, :recv_timeout, 30_000)

    req_opts = [
      method: method,
      url: url,
      headers: headers,
      body: body,
      receive_timeout: timeout,
      retry: false,
      # Disable default response body decoding — ExAws handles that itself
      decode_body: false
    ]

    case Req.request(req_opts) do
      {:ok, %Req.Response{status: status, headers: resp_headers, body: body}} ->
        # ExAws expects headers as a list of {String, String} tuples
        flat_headers =
          Enum.flat_map(resp_headers, fn {key, values} ->
            Enum.map(List.wrap(values), &{key, &1})
          end)

        {:ok, %{status_code: status, headers: flat_headers, body: body}}

      {:error, exception} ->
        {:error, %{reason: Exception.message(exception)}}
    end
  end
end
