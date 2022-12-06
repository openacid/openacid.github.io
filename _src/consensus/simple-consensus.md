## Proposer

### phase-1

request: {id}

response:{rnd}

```rust
```



### phase-2

request: {id, rnd, event}

response: {id}



## Acceptor

```rust
Acceptor {
  state: Vec<{id: Id, e: Option<Event>}>,
}
```



### handle-phase-1

```
handle_phase_1_req(req: Phase1Req) {
	let last = state.last();
	if req.id != last.id {
		state.push({id: req.id, e: None});		
	}
	return Phase1Response{rnd: state.len()-1}
}
```

## handle-phase-2

```
handle_phase_2_req(res: Phase2Req) {
	let last = state.last();
	if req.id == last.id {
		if req.rnd == state.len() {
			state.push({id: req.id, e: req.event});
		}
	}
	return Phase2Response{id: last.id, rnd: state.len()-1}
}
```

