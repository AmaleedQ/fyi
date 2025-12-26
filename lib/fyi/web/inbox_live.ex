if Code.ensure_loaded?(Phoenix.LiveView) do
  defmodule FYI.Web.InboxLive do
    @moduledoc """
    LiveView for the FYI admin inbox.

    Displays recent events with filtering and detail view.
    """

    use Phoenix.LiveView
    import Phoenix.HTML, only: [raw: 1]

    alias FYI.Schema.Event

    @per_page 500

    @impl true
    def mount(_params, _session, socket) do
      {:ok,
       socket
       |> assign(:page_title, "FYI Events")
       |> assign(:search, "")
       |> assign(:selected_event, nil)
       |> assign(:per_page, @per_page)
       |> assign(:chart_id, System.unique_integer([:positive]))}
    end

    @impl true
    def handle_params(params, _uri, socket) do
      time_range = params["range"] || "7d"
      event_id = params["id"]

      socket =
        socket
        |> assign(:time_range, time_range)
        |> assign(:chart_id, System.unique_integer([:positive]))
        |> load_events()
        |> compute_field_stats()
        |> compute_histogram()

      socket =
        if event_id do
          load_event_detail(socket, event_id)
        else
          assign(socket, :selected_event, nil)
        end

      {:noreply, socket}
    end

    @impl true
    def handle_event("search", %{"search" => search}, socket) do
      {:noreply,
       socket
       |> assign(:search, search)
       |> load_events()
       |> compute_field_stats()
       |> compute_histogram()
       |> assign(:chart_id, System.unique_integer([:positive]))}
    end

    @impl true
    def handle_event("time_range", %{"range" => range}, socket) do
      {:noreply, push_patch(socket, to: "/fyi?range=#{range}")}
    end

    @impl true
    def handle_event("close_detail", _, socket) do
      range = socket.assigns.time_range
      {:noreply, push_patch(socket, to: "/fyi?range=#{range}")}
    end

    @impl true
    def render(assigns) do
      ~H"""
      <div class="fyi-app">
        <script src="https://cdn.jsdelivr.net/npm/chart.js@4.4.1/dist/chart.umd.min.js"></script>
        <style>
          @import url('https://fonts.googleapis.com/css2?family=Inter:wght@400;500;600&display=swap');

          .fyi-app {
            font-family: 'Inter', -apple-system, BlinkMacSystemFont, sans-serif;
            background: #f8fafc;
            min-height: 100vh;
            color: #1e293b;
            font-size: 13px;
            line-height: 1.5;
          }

          .fyi-container {
            display: flex;
            height: 100vh;
          }

          .fyi-main {
            flex: 1;
            display: flex;
            flex-direction: column;
            overflow: hidden;
          }

          .fyi-header {
            background: white;
            border-bottom: 1px solid #e2e8f0;
            padding: 12px 20px;
            display: flex;
            align-items: center;
            gap: 12px;
          }

          .fyi-search {
            flex: 1;
            display: flex;
            align-items: center;
            background: #f1f5f9;
            border-radius: 6px;
            padding: 8px 12px;
            gap: 8px;
          }

          .fyi-search-icon {
            color: #94a3b8;
          }

          .fyi-search input {
            flex: 1;
            border: none;
            background: transparent;
            font-size: 13px;
            color: #1e293b;
            outline: none;
          }

          .fyi-search input::placeholder {
            color: #94a3b8;
          }

          .fyi-header-actions {
            display: flex;
            align-items: center;
            gap: 8px;
          }

          .fyi-time-select {
            padding: 8px 12px;
            border: 1px solid #e2e8f0;
            border-radius: 6px;
            background: white;
            font-size: 13px;
            color: #1e293b;
            cursor: pointer;
          }

          .fyi-btn {
            padding: 8px 16px;
            border-radius: 6px;
            font-size: 13px;
            font-weight: 500;
            cursor: pointer;
            border: none;
          }

          .fyi-btn-primary {
            background: #3b82f6;
            color: white;
          }

          .fyi-btn-primary:hover {
            background: #2563eb;
          }

          .fyi-chart-container {
            background: white;
            border-bottom: 1px solid #e2e8f0;
            padding: 16px 20px;
            height: 100px;
          }

          .fyi-content {
            display: flex;
            flex: 1;
            overflow: hidden;
          }

          .fyi-events-panel {
            flex: 1;
            overflow-y: auto;
            background: white;
          }

          .fyi-event-row {
            display: flex;
            align-items: flex-start;
            padding: 8px 20px;
            border-bottom: 1px solid #f1f5f9;
            cursor: pointer;
            transition: background 0.1s;
            gap: 12px;
            text-decoration: none;
            color: inherit;
          }

          .fyi-event-row:hover {
            background: #f8fafc;
          }

          .fyi-event-icon {
            color: #94a3b8;
            margin-top: 2px;
          }

          .fyi-event-time {
            color: #64748b;
            font-size: 12px;
            white-space: nowrap;
            min-width: 140px;
          }

          .fyi-event-level {
            font-size: 11px;
            font-weight: 500;
            padding: 2px 6px;
            border-radius: 3px;
            text-transform: uppercase;
            min-width: 36px;
            text-align: center;
          }

          .fyi-level-info {
            background: #dbeafe;
            color: #1d4ed8;
          }

          .fyi-level-error {
            background: #fee2e2;
            color: #dc2626;
          }

          .fyi-level-warn {
            background: #fef3c7;
            color: #d97706;
          }

          .fyi-event-content {
            flex: 1;
            min-width: 0;
            display: flex;
            flex-wrap: wrap;
            gap: 4px 12px;
            align-items: baseline;
          }

          .fyi-event-name {
            color: #1e293b;
            font-weight: 500;
          }

          .fyi-event-field {
            color: #64748b;
          }

          .fyi-event-field-key {
            color: #3b82f6;
          }

          .fyi-event-field-value {
            color: #1e293b;
          }

          .fyi-fields-panel {
            width: 280px;
            background: white;
            border-left: 1px solid #e2e8f0;
            overflow-y: auto;
            padding: 16px;
          }

          .fyi-fields-header {
            font-weight: 600;
            color: #1e293b;
            margin-bottom: 4px;
          }

          .fyi-fields-subheader {
            font-size: 12px;
            color: #64748b;
            margin-bottom: 16px;
          }

          .fyi-fields-search {
            width: 100%;
            padding: 8px 12px;
            border: 1px solid #e2e8f0;
            border-radius: 6px;
            font-size: 13px;
            margin-bottom: 16px;
            box-sizing: border-box;
          }

          .fyi-field-item {
            display: flex;
            align-items: center;
            justify-content: space-between;
            padding: 6px 0;
            border-bottom: 1px solid #f1f5f9;
          }

          .fyi-field-name {
            color: #1e293b;
            font-weight: 500;
          }

          .fyi-field-meta {
            display: flex;
            align-items: center;
            gap: 8px;
            font-size: 12px;
            color: #94a3b8;
          }

          .fyi-field-type {
            color: #64748b;
          }

          .fyi-status-bar {
            background: white;
            border-top: 1px solid #e2e8f0;
            padding: 8px 20px;
            font-size: 12px;
            color: #64748b;
            display: flex;
            gap: 24px;
          }

          .fyi-empty {
            padding: 48px;
            text-align: center;
            color: #94a3b8;
          }

          .fyi-modal-overlay {
            position: fixed;
            inset: 0;
            background: rgba(0,0,0,0.4);
            display: flex;
            align-items: center;
            justify-content: center;
            z-index: 50;
          }

          .fyi-modal {
            background: white;
            border-radius: 8px;
            max-width: 640px;
            width: 90%;
            max-height: 80vh;
            overflow: auto;
            box-shadow: 0 20px 25px -5px rgba(0,0,0,0.1);
          }

          .fyi-modal-header {
            padding: 16px 20px;
            border-bottom: 1px solid #e2e8f0;
            display: flex;
            justify-content: space-between;
            align-items: center;
          }

          .fyi-modal-header h2 {
            font-size: 15px;
            font-weight: 600;
            margin: 0;
          }

          .fyi-modal-close {
            background: none;
            border: none;
            font-size: 20px;
            cursor: pointer;
            color: #94a3b8;
            padding: 0;
            line-height: 1;
          }

          .fyi-modal-close:hover {
            color: #64748b;
          }

          .fyi-modal-body {
            padding: 20px;
          }

          .fyi-detail-grid {
            display: grid;
            grid-template-columns: 100px 1fr;
            gap: 12px 16px;
            margin-bottom: 20px;
          }

          .fyi-detail-label {
            font-size: 12px;
            color: #64748b;
          }

          .fyi-detail-value {
            color: #1e293b;
            word-break: break-all;
          }

          .fyi-payload {
            background: #f8fafc;
            padding: 16px;
            border-radius: 6px;
            font-family: 'SF Mono', Monaco, 'Cascadia Code', monospace;
            font-size: 12px;
            white-space: pre-wrap;
            overflow-x: auto;
            border: 1px solid #e2e8f0;
          }

          .fyi-payload-label {
            font-size: 12px;
            color: #64748b;
            margin-bottom: 8px;
          }
        </style>


        <div class="fyi-container">
          <div class="fyi-main">
            <div class="fyi-header">
              <div class="fyi-search">
                <svg class="fyi-search-icon" width="16" height="16" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2">
                  <circle cx="11" cy="11" r="8"></circle>
                  <path d="m21 21-4.35-4.35"></path>
                </svg>
                <form phx-change="search" style="flex:1;display:flex;">
                  <input
                    type="text"
                    name="search"
                    value={@search}
                    placeholder="Search"
                    phx-debounce="200"
                  />
                </form>
              </div>
              <div class="fyi-header-actions">
                <form phx-change="time_range">
                  <select name="range" class="fyi-time-select">
                    <option value="5m" selected={@time_range == "5m"}>Past 5 minutes</option>
                    <option value="15m" selected={@time_range == "15m"}>Past 15 minutes</option>
                    <option value="1h" selected={@time_range == "1h"}>Past 1 hour</option>
                    <option value="24h" selected={@time_range == "24h"}>Past 24 hours</option>
                    <option value="7d" selected={@time_range == "7d"}>Last 7 days</option>
                    <option value="30d" selected={@time_range == "30d"}>Last 30 days</option>
                    <option value="6mo" selected={@time_range == "6mo"}>Last 6 months</option>
                    <option value="1y" selected={@time_range == "1y"}>Last year</option>
                    <option value="all" selected={@time_range == "all"}>All time</option>
                  </select>
                </form>
                <button class="fyi-btn fyi-btn-primary" phx-click="search">Search</button>
              </div>
            </div>

            <div class="fyi-chart-container">
              <canvas
                id={"fyi-histogram-#{@chart_id}"}
                phx-hook="FYIChart"
                data-histogram={Jason.encode!(@histogram)}
              ></canvas>
            </div>

            <div class="fyi-content">
              <div class="fyi-events-panel">
                <%= if Enum.empty?(@events) do %>
                  <div class="fyi-empty">
                    <p>No events found</p>
                  </div>
                <% else %>
                  <%= for event <- @events do %>
                    <.link patch={"/fyi/events/#{event.id}"} class="fyi-event-row">
                      <svg class="fyi-event-icon" width="14" height="14" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2">
                        <path d="M14 2H6a2 2 0 0 0-2 2v16a2 2 0 0 0 2 2h12a2 2 0 0 0 2-2V8z"></path>
                        <polyline points="14 2 14 8 20 8"></polyline>
                      </svg>
                      <span class="fyi-event-time"><%= format_time_full(event.inserted_at) %></span>
                      <span class={"fyi-event-level #{level_class(event.name)}"}><%= level_text(event.name) %></span>
                      <div class="fyi-event-content">
                        <span class="fyi-event-name"><%= event.name %></span>
                        <%= if event.actor do %>
                          <span class="fyi-event-field">
                            <span class="fyi-event-field-key">actor:</span>
                            <span class="fyi-event-field-value"><%= event.actor %></span>
                          </span>
                        <% end %>
                        <%= for {k, v} <- Enum.take(event.payload || %{}, 3) do %>
                          <span class="fyi-event-field">
                            <span class="fyi-event-field-key"><%= k %>:</span>
                            <span class="fyi-event-field-value"><%= format_value(v) %></span>
                          </span>
                        <% end %>
                      </div>
                    </.link>
                  <% end %>
                <% end %>
              </div>

              <div class="fyi-fields-panel">
                <div class="fyi-fields-header">Fields</div>
                <div class="fyi-fields-subheader">Discovered fields for the query.</div>
                <input type="text" class="fyi-fields-search" placeholder="Filter" />
                <%= for {field, %{type: type, pct: pct}} <- @field_stats do %>
                  <div class="fyi-field-item">
                    <span class="fyi-field-name"><%= field %></span>
                    <span class="fyi-field-meta">
                      <span class="fyi-field-type"><%= type %></span>
                      <span><%= pct %>%</span>
                    </span>
                  </div>
                <% end %>
              </div>
            </div>

            <div class="fyi-status-bar">
              <span><strong>Limit:</strong> <%= @per_page %></span>
              <span><strong>Matched:</strong> <%= length(@events) %></span>
            </div>
          </div>
        </div>

        <%= if @selected_event do %>
          <div class="fyi-modal-overlay" phx-click="close_detail">
            <div class="fyi-modal" phx-click-away="close_detail">
              <div class="fyi-modal-header">
                <h2><%= @selected_event.name %></h2>
                <button class="fyi-modal-close" phx-click="close_detail">&times;</button>
              </div>
              <div class="fyi-modal-body">
                <div class="fyi-detail-grid">
                  <span class="fyi-detail-label">Event ID</span>
                  <span class="fyi-detail-value"><%= @selected_event.id %></span>

                  <span class="fyi-detail-label">Actor</span>
                  <span class="fyi-detail-value"><%= @selected_event.actor || "-" %></span>

                  <span class="fyi-detail-label">Source</span>
                  <span class="fyi-detail-value"><%= @selected_event.source || "-" %></span>

                  <span class="fyi-detail-label">Time</span>
                  <span class="fyi-detail-value"><%= @selected_event.inserted_at %></span>

                  <%= if map_size(@selected_event.tags || %{}) > 0 do %>
                    <span class="fyi-detail-label">Tags</span>
                    <span class="fyi-detail-value">
                      <%= for {k, v} <- @selected_event.tags do %>
                        <span style="background:#e0e7ff;color:#4338ca;padding:2px 6px;border-radius:3px;font-size:12px;margin-right:4px;"><%= k %>: <%= v %></span>
                      <% end %>
                    </span>
                  <% end %>
                </div>

                <div class="fyi-payload-label">Payload</div>
                <pre class="fyi-payload"><%= Jason.encode!(@selected_event.payload, pretty: true) %></pre>
              </div>
            </div>
          </div>
        <% end %>
      </div>

      """
    end

    defp load_events(socket) do
      repo = Application.get_env(:fyi, :repo)

      if repo && Code.ensure_loaded?(Event) do
        import Ecto.Query

        since = time_range_since(socket.assigns.time_range)

        query =
          from(e in Event,
            where: e.inserted_at >= ^since,
            order_by: [desc: e.inserted_at],
            limit: @per_page
          )

        query =
          if socket.assigns[:search] && socket.assigns.search != "" do
            search_filter = "%#{socket.assigns.search}%"

            from(e in query,
              where: ilike(e.name, ^search_filter) or ilike(e.actor, ^search_filter)
            )
          else
            query
          end

        events = repo.all(query)
        assign(socket, :events, events)
      else
        assign(socket, :events, [])
      end
    end

    defp time_range_since(range) do
      now = DateTime.utc_now()

      case range do
        "5m" -> DateTime.add(now, -5, :minute)
        "15m" -> DateTime.add(now, -15, :minute)
        "1h" -> DateTime.add(now, -1, :hour)
        "24h" -> DateTime.add(now, -24, :hour)
        "7d" -> DateTime.add(now, -7, :day)
        "30d" -> DateTime.add(now, -30, :day)
        "6mo" -> DateTime.add(now, -180, :day)
        "1y" -> DateTime.add(now, -365, :day)
        "all" -> ~U[2000-01-01 00:00:00Z]
        _ -> DateTime.add(now, -7, :day)
      end
    end

    defp time_range_seconds(range) do
      case range do
        "5m" -> 5 * 60
        "15m" -> 15 * 60
        "1h" -> 60 * 60
        "24h" -> 24 * 60 * 60
        "7d" -> 7 * 24 * 60 * 60
        "30d" -> 30 * 24 * 60 * 60
        "6mo" -> 180 * 24 * 60 * 60
        "1y" -> 365 * 24 * 60 * 60
        "all" -> 365 * 10 * 24 * 60 * 60
        _ -> 7 * 24 * 60 * 60
      end
    end

    defp compute_field_stats(socket) do
      events = socket.assigns[:events] || []
      total = max(length(events), 1)

      base_fields = [
        {"id", "string", 100},
        {"name", "string", 100},
        {"actor", "string", count_non_nil(events, :actor) * 100 / total},
        {"source", "string", count_non_nil(events, :source) * 100 / total}
      ]

      payload_fields =
        events
        |> Enum.flat_map(fn e -> Map.keys(e.payload || %{}) end)
        |> Enum.frequencies()
        |> Enum.map(fn {k, count} ->
          {to_string(k), infer_type(events, k), round(count * 100 / total)}
        end)
        |> Enum.sort_by(fn {_, _, pct} -> -pct end)

      all_fields =
        (base_fields ++ payload_fields)
        |> Enum.map(fn {name, type, pct} -> {name, %{type: type, pct: round(pct)}} end)

      assign(socket, :field_stats, all_fields)
    end

    defp count_non_nil(events, field) do
      Enum.count(events, fn e -> Map.get(e, field) != nil end)
    end

    defp infer_type(events, key) do
      sample =
        events
        |> Enum.find_value(fn e ->
          case e.payload do
            %{^key => v} -> v
            _ -> nil
          end
        end)

      case sample do
        nil -> "string"
        v when is_integer(v) -> "number"
        v when is_float(v) -> "number"
        v when is_binary(v) -> "string"
        v when is_boolean(v) -> "boolean"
        _ -> "string"
      end
    end

    defp compute_histogram(socket) do
      events = socket.assigns[:events] || []
      time_range = socket.assigns[:time_range] || "5m"

      # 60 buckets across the time range
      buckets = 60
      total_seconds = time_range_seconds(time_range)
      bucket_size = max(div(total_seconds, buckets), 1)

      now = DateTime.utc_now()

      counts =
        events
        |> Enum.reduce(%{}, fn event, acc ->
          if event.inserted_at do
            diff = DateTime.diff(now, event.inserted_at, :second)
            bucket = min(div(diff, bucket_size), buckets - 1)
            Map.update(acc, bucket, 1, &(&1 + 1))
          else
            acc
          end
        end)

      values = Enum.map(0..(buckets - 1), fn i -> Map.get(counts, buckets - 1 - i, 0) end)

      labels =
        Enum.map(0..(buckets - 1), fn i ->
          seconds_ago = (buckets - 1 - i) * bucket_size
          format_time_ago(seconds_ago)
        end)

      assign(socket, :histogram, %{labels: labels, values: values})
    end

    defp format_time_ago(seconds) when seconds < 60, do: "#{seconds}s ago"
    defp format_time_ago(seconds) when seconds < 3600, do: "#{div(seconds, 60)}m ago"
    defp format_time_ago(seconds), do: "#{div(seconds, 3600)}h ago"

    defp load_event_detail(socket, id) do
      repo = Application.get_env(:fyi, :repo)

      if repo && Code.ensure_loaded?(Event) do
        case repo.get(Event, id) do
          nil -> assign(socket, :selected_event, nil)
          event -> assign(socket, :selected_event, event)
        end
      else
        assign(socket, :selected_event, nil)
      end
    end

    defp format_time_full(nil), do: "-"

    defp format_time_full(datetime) do
      Calendar.strftime(datetime, "%b %d, %H:%M:%S %p")
    end

    defp format_value(v) when is_binary(v), do: v
    defp format_value(v) when is_number(v), do: to_string(v)
    defp format_value(v), do: inspect(v)

    defp level_class(name) do
      cond do
        String.contains?(name, "error") -> "fyi-level-error"
        String.contains?(name, "warn") -> "fyi-level-warn"
        true -> "fyi-level-info"
      end
    end

    defp level_text(name) do
      cond do
        String.contains?(name, "error") -> "ERROR"
        String.contains?(name, "warn") -> "WARN"
        true -> "INFO"
      end
    end
  end
end
