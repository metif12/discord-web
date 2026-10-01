module discord

import time
import json2
import cdp

// State is what one probe of the message list reported.
pub struct State {
pub:
	url             string
	rendered        int
	scroll_top      int
	scroll_height   int
	client_height   int
	x               int
	y               int
	oldest_timestamp string
	newest_timestamp string
}

// Message is one collected message.
pub struct Message {
pub:
	id        string
	author    string
	timestamp string
	content   string
}

// Result is a full walk of a channel's history.
pub struct HistoryResult {
pub:
	url       string
	total     int
	passes    int
	stopped   string
	oldest    string
	newest    string
	messages  []Message
}

// StepPlan is how a single pass should scroll.
//
// The values were tuned against Discord's own scroller rather than guessed.
// Large deltas overshoot the top, and Discord then rebases scrollTop with a
// bounce, which pushes the list back down and wastes the pass. Small deltas
// creep reliably to the boundary, so a pass is a burst of them rather than one
// big jump.
const ticks_per_burst = 5
const tick_delta = -400
const tick_gap_ms = 60
const down_ticks = 3
// Below this scroll position the list is treated as parked at the top, which is
// where Discord stops fetching and needs a nudge down before it will fetch again.
const climb_threshold = 40
const settle_ms = 2500
const settle_retries = 4
// How many climbs in a row may load nothing before the channel start is called.
const dry_pass_limit = 4
const max_passes = 80
const max_bursts_per_pass = 40
// Probing walks the whole rendered list, so it is done every few bursts rather
// than after each one. Between probes the climb continues blindly, which is
// cheaper and still stops as soon as the top is reached.
const probe_every_bursts = 3
// Wall-clock budget for one walk. A channel with years of history needs more
// passes than any caller is willing to wait for, so the walk reports what it
// gathered instead of running until the tool times out.
const budget_ms = 240000

// sleep_ms waits between scroll actions. Discord rebases scrollTop while it loads
// an older window, so the gaps between wheel events are load-bearing: without
// them the events arrive faster than anything renders and most are wasted.
fn sleep_ms(dur int) {
	time.sleep(dur * time.millisecond)
}

// now_ms is the monotonic clock in milliseconds, for the walk's time budget.
//
// sys_mono_now counts nanoseconds, so it is divided down; comparing its raw value
// against a millisecond budget would expire the budget immediately.
fn now_ms() i64 {
	return time.sys_mono_now() / 1_000_000
}

// probe reads the message list's current state.
pub fn probe(mut client cdp.Client) !State {
	raw := client.eval('(' + probe_js() + ')()') or { return err }
	text := raw as string
	obj := decode(text) or { return err }
	return State{
		url:              str(obj, 'url')
		rendered:         num(obj, 'rendered')
		scroll_top:       num(obj, 'scroll_top')
		scroll_height:    num(obj, 'scroll_height')
		client_height:    num(obj, 'client_height')
		x:                num(obj, 'x')
		y:                num(obj, 'y')
		oldest_timestamp: str(obj, 'oldest_timestamp')
		newest_timestamp: str(obj, 'newest_timestamp')
	}
}

// collect_absorb snapshots the rendered window into the accumulator. Repeated
// snapshots overlap heavily, so ids are used to keep each message once.
fn collect_absorb(mut client cdp.Client, mut seen map[string]Message) !int {
	raw := client.eval('(' + read_js() + ')()') or { return err }
	text := raw as string
	items := decode(text) or { return err }
	list := items['messages'] or { json2.Any('null') }
	if list !is []json2.Any {
		return 0
	}
	mut added := 0
	for item in list as []json2.Any {
		entry := as_obj(item) or { continue }
		id := str(entry, 'id')
		if id == '' || id in seen {
			continue
		}
		seen[id] = Message{
			id:        id
			author:    str(entry, 'author')
			timestamp: str(entry, 'timestamp')
			content:   str(entry, 'content')
		}
		added++
	}
	return added
}

// walk_to_start climbs to the top of the loaded window with trusted wheel events
// and returns the state it reached.
//
// Climbing is what makes Discord fetch the next older window. It stops in two
// cases: the list parked at the top, or the scroll height grew, which means
// Discord prepended a window and rebased scrollTop. In the second case the climb
// has to resume from the new position, so the caller runs another pass.
//
// The wheel deltas are deliberately small. A large jump overshoots the top, and
// Discord answers with a bounce that pushes the list back down, wasting the pass.
fn walk_to_start(mut client cdp.Client, mut st State) !State {
	for burst in 0 .. max_bursts_per_pass {
		// Drop back down before climbing again. Discord arms its fetch-on-scroll-up
		// hook from the scroll transition, and a wheel burst that starts at the
		// very top sends no transition, so nothing loads and the walk stalls.
		if st.scroll_top <= climb_threshold {
			for _ in 0 .. down_ticks {
				client.wheel(st.x, st.y, -tick_delta) or { return err }
				sleep_ms(tick_gap_ms)
			}
			sleep_ms(150)
		}
		for _ in 0 .. ticks_per_burst {
			client.wheel(st.x, st.y, tick_delta) or { return err }
			sleep_ms(tick_gap_ms)
		}
		// Climbing between probes is blind, but re-reading the list on every burst
		// costs more than the climb itself.
		if (burst + 1) % probe_every_bursts != 0 {
			continue
		}
		prev_height := st.scroll_height
		st = probe(mut client) or { return err }
		// Prepended history: hand back so the caller can absorb it and climb again.
		if st.scroll_height > prev_height {
			return st
		}
		// Neither the height nor the position moved, so further wheel events will
		// not either: this is the channel start.
		if st.scroll_height == prev_height && st.scroll_top == 0 {
			return st
		}
	}
	st = probe(mut client) or { return err }
	return st
}

// collect walks the open channel's whole history.
//
// It stops when the channel start is reached, when a pass loads nothing new, or
// when the pass budget runs out. Returns everything gathered so far in any case,
// because a partial history is still useful and the caller can ask for more.
pub fn collect(mut client cdp.Client, limit int) !HistoryResult {
	// Input dispatch blocks until the renderer acknowledges it, and a background
	// tab never does, so the tab must be active before any wheel is sent.
	client.bring_to_front() or { return err }

	bound := if limit > 0 { limit } else { 500 }
	mut st := probe(mut client) or { return err }
	mut seen := map[string]Message{}
	collect_absorb(mut client, mut seen) or { return err }

	mut passes := 0
	mut stopped := ''
	// Discord skips a fetch now and then even with the list parked at the top, so
	// one empty pass does not mean the channel start. A few in a row do.
	mut dry_passes := 0
	// A deep channel can hold far more history than a tool call may spend on it,
	// so the walk is bounded by wall-clock time as well as by passes.
	deadline := now_ms() + i64(budget_ms)

	for passes < max_passes {
		passes++
		before_height := st.scroll_height
		before_oldest := st.oldest_timestamp

		// Climb until the top of the loaded window, then let Discord fetch. The
		// height check below is deliberately made after this settles: growth shows
		// up a moment later, and judging it too early would end the walk on the
		// first pass.
		st = walk_to_start(mut client, mut st) or { return err }

		// Wait for the fetch to land. Discord rebases scrollTop as the window
		// arrives, so the climb must keep going while the height is still moving;
		// stopping at the first settled read would leave history unloaded.
		mut settled := false
		for _ in 0 .. settle_retries {
			sleep_ms(settle_ms)
			st = probe(mut client) or { return err }
			added := collect_absorb(mut client, mut seen) or { return err }
			grew := st.scroll_height > before_height
				|| st.oldest_timestamp != before_oldest || added > 0
			if grew {
				settled = true
				if seen.len >= bound {
					stopped = 'reached the requested message limit'
				}
				break
			}
		}
		if stopped != '' {
			break
		}
		if settled {
			dry_passes = 0
			if seen.len >= bound {
				stopped = 'reached the requested message limit'
				break
			}
			if now_ms() > deadline {
				stopped = 'ran out of time, so this is part of the history'
				break
			}
			continue
		}
		// Discord ignored this climb. Try again before concluding anything.
		dry_passes++
		if dry_passes >= dry_pass_limit {
			stopped = 'reached the start of the channel'
			break
		}
	}
	if stopped == '' {
		stopped = 'used up the scroll pass budget'
	}

	// Snowflakes are numeric, so sorting by id is chronological.
	mut msgs := seen.values()
	msgs.sort_with_compare(fn (a &Message, b &Message) int {
		x := a.id.i64()
		y := b.id.i64()
		return if x < y { -1 } else if x > y { 1 } else { 0 }
	})

	return HistoryResult{
		url:      st.url
		total:    msgs.len
		passes:   passes
		stopped:  stopped
		oldest:   if msgs.len > 0 { msgs[0].timestamp } else { '' }
		newest:   if msgs.len > 0 { msgs[msgs.len - 1].timestamp } else { '' }
		messages: msgs
	}
}

// probe_js returns the script that reports the message list's state.
fn probe_js() string {
	return $embed_file('js/history.js').to_string()
}

// read_js returns the script that snapshots the rendered window.
fn read_js() string {
	return $embed_file('js/collect.js').to_string()
}

// decode parses a probe's JSON string result.
fn decode(text string) !map[string]json2.Any {
	return json2.decode[map[string]json2.Any](text) or {
		return error('probe returned malformed JSON: ${text[..200]}')
	}
}

// str reads a string field from a decoded object.
fn str(obj map[string]json2.Any, key string) string {
	v := obj[key] or { return '' }
	if v is string {
		return v as string
	}
	return ''
}

// num reads an integer field from a decoded object.
fn num(obj map[string]json2.Any, key string) int {
	v := obj[key] or { return 0 }
	if v is f64 {
		return int(v as f64)
	}
	if v is int {
		return v as int
	}
	return 0
}

// as_obj narrows a decoded value to an object.
fn as_obj(v json2.Any) ?map[string]json2.Any {
	if v is map[string]json2.Any {
		return v as map[string]json2.Any
	}
	return none
}