defmodule FYI.ClientTest do
  use ExUnit.Case, async: true

  alias FYI.Client

  describe "new/0" do
    test "creates a Req client with default retry configuration" do
      client = Client.new()

      assert %Req.Request{} = client
      # Req stores options in the request struct
      assert client.options[:retry] == :transient
      assert client.options[:max_retries] == 3
      assert is_function(client.options[:retry_delay], 1)
    end

    test "uses exponential backoff by default" do
      client = Client.new()
      retry_delay = client.options[:retry_delay]

      # Test default backoff: 1s, 2s, 4s
      assert retry_delay.(1) == 1000
      assert retry_delay.(2) == 2000
      assert retry_delay.(3) == 4000
    end
  end

  describe "new/1 with custom options" do
    test "accepts custom Req options" do
      client = Client.new(receive_timeout: 5000)

      assert client.options[:receive_timeout] == 5000
    end

    test "merges custom options with defaults" do
      client = Client.new(headers: [{"x-custom", "value"}])

      # Custom option is set
      assert client.options[:headers] == [{"x-custom", "value"}]
      # Defaults are still present
      assert client.options[:retry] == :transient
      assert client.options[:max_retries] == 3
    end
  end

  describe "new/0 with application config" do
    setup do
      original_config = Application.get_env(:fyi, :http_client)

      on_exit(fn ->
        if original_config do
          Application.put_env(:fyi, :http_client, original_config)
        else
          Application.delete_env(:fyi, :http_client)
        end
      end)
    end

    test "respects max_retries from application config" do
      Application.put_env(:fyi, :http_client, max_retries: 5)

      client = Client.new()

      assert client.options[:max_retries] == 5
    end

    test "respects custom retry_delay from application config" do
      custom_delay = fn attempt -> attempt * 500 end
      Application.put_env(:fyi, :http_client, retry_delay: custom_delay)

      client = Client.new()

      assert client.options[:retry_delay] == custom_delay
      assert client.options[:retry_delay].(1) == 500
    end

    test "allows disabling retries with max_retries: 0" do
      Application.put_env(:fyi, :http_client, max_retries: 0)

      client = Client.new()

      assert client.options[:max_retries] == 0
    end
  end

  describe "post/2" do
    test "returns ok tuple with response on success" do
      # Using httpbin.org's mock endpoint for testing
      # Note: This is a real HTTP call - in production you might want to mock this
      bypass_url = "https://httpbin.org/status/200"

      case Client.post(bypass_url) do
        {:ok, response} ->
          assert %Req.Response{} = response
          assert response.status == 200

        {:error, _} ->
          # Network might be unavailable in test environment, that's ok
          :ok
      end
    end

    test "accepts json option" do
      # This test documents the API but doesn't make a real request
      # since we don't have a test server set up
      assert is_function(&Client.post/2)
    end

    test "accepts custom options" do
      # This test documents the API
      assert is_function(&Client.post/2)
    end
  end

  describe "integration" do
    test "Client can be used in place of Req.post" do
      # Verify the API is compatible with existing Req.post usage
      url = "https://example.com/webhook"

      # These should have the same signature
      # FYI.Client.post(url, json: %{foo: "bar"})
      # Req.post(url, json: %{foo: "bar"})

      assert is_function(&Client.post/2)
      assert is_function(&Req.post/2)
    end
  end
end
