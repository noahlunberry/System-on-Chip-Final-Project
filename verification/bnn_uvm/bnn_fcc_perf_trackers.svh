`ifndef _BNN_FCC_PERF_TRACKERS_SVH_
`define _BNN_FCC_PERF_TRACKERS_SVH_

class bnn_fcc_latency_tracker;
    local realtime start_times[int];
    local real     latencies_cycles[$];
    local realtime latencies_time[$];
    real           clock_period_ns;

    function new(real period);
        this.clock_period_ns = period;
    endfunction

    function void start_event_at(int id, realtime start_time);
        start_times[id] = start_time;
    endfunction

    function void start_event(int id);
        start_event_at(id, $realtime);
    endfunction

    function void clear_event(int id);
        if (start_times.exists(id))
            start_times.delete(id);
    endfunction

    function void end_event_at(int id, realtime end_time);
        if (start_times.exists(id)) begin
            realtime dur = end_time - start_times[id];
            latencies_time.push_back(dur);
            latencies_cycles.push_back(dur / clock_period_ns);
            start_times.delete(id);
        end
        else begin
            $warning("bnn_fcc_latency_tracker: end_event called for unknown ID %0d", id);
        end
    endfunction

    function void end_event(int id);
        end_event_at(id, $realtime);
    endfunction

    function real get_avg_cycles();
        return (latencies_cycles.size() > 0) ? (latencies_cycles.sum() / latencies_cycles.size()) : 0;
    endfunction

    function realtime get_avg_time();
        return (latencies_time.size() > 0) ? (latencies_time.sum() / latencies_time.size()) : 0;
    endfunction
endclass

class bnn_fcc_throughput_tracker;
    local realtime first_start_time;
    local realtime last_end_time;
    real           clock_period_ns;

    function new(real period);
        this.clock_period_ns = period;
        this.first_start_time = 0;
        this.last_end_time = 0;
    endfunction

    function void start_test_at(realtime start_time);
        if (first_start_time == 0)
            first_start_time = start_time;
    endfunction

    function void start_test();
        start_test_at($realtime);
    endfunction

    function void sample_end_at(realtime end_time);
        last_end_time = end_time;
    endfunction

    function void sample_end();
        sample_end_at($realtime);
    endfunction

    function real get_outputs_per_sec(int total_count);
        realtime total_window;

        total_window = last_end_time - first_start_time;
        return (total_window > 0) ? (total_count / (total_window * 1e-9)) : 0;
    endfunction

    function real get_avg_cycles_per_output(int total_count);
        realtime total_window;

        total_window = last_end_time - first_start_time;
        return (total_count > 0) ? (real'(total_window) / (clock_period_ns * total_count)) : 0;
    endfunction
endclass

`endif
