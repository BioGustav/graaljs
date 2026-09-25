/*
 * Copyright (c) 2026, Oracle and/or its affiliates. All rights reserved.
 * DO NOT ALTER OR REMOVE COPYRIGHT NOTICES OR THIS FILE HEADER.
 *
 * Licensed under the Universal Permissive License v 1.0 as shown at http://oss.oracle.com/licenses/upl.
 */

/**
 * WebAssembly memory64 JavaScript API tests.
 *
 * @option webassembly
 * @option worker
 * @option wasm.Memory64
 * @option wasm.Threads
 * @option wasm.UseUnsafeMemory
 */

load('../js/assert.js');

// i64-indexed memories use BigInt for limits, growth deltas, and growth results.
{
    const memory = new WebAssembly.Memory({initial: 1n, maximum: 3n, address: 'i64'});
    assertSame(1n, memory.grow(1n));
    assertSame(2n, memory.grow(0n));
    assertThrows(() => memory.grow(1), TypeError);
    assertThrows(() => memory.grow(2n), RangeError);

    assertThrows(() => new WebAssembly.Memory({initial: 1, address: 'i64'}), TypeError);
    assertThrows(() => new WebAssembly.Memory({initial: 1n, address: 'i32'}), TypeError);
    assertThrows(() => new WebAssembly.Memory({initial: 1n, address: 'invalid'}), TypeError);
    assertThrows(() => new WebAssembly.Memory({initial: -1n, address: 'i64'}), TypeError);
    new WebAssembly.Memory({initial: 0n, maximum: (1n << 37n) - 1n, address: 'i64'});
    assertThrows(() => new WebAssembly.Memory({initial: 0n, maximum: 1n << 37n, address: 'i64'}), RangeError);

    // (module
    //   (import "m" "mem" (memory i64 1 3))
    // )
    const importModule = new WebAssembly.Module(new Uint8Array([
        0x00, 0x61, 0x73, 0x6d, 0x01, 0x00, 0x00, 0x00,
        0x02, 0x0b, 0x01, 0x01, 0x6d, 0x03, 0x6d, 0x65, 0x6d, 0x02, 0x05, 0x01, 0x03,
    ]));
    new WebAssembly.Instance(importModule, {m: {mem: memory}});
    const memory32 = new WebAssembly.Memory({initial: 1, maximum: 3});
    assertThrows(() => new WebAssembly.Instance(importModule, {m: {mem: memory32}}), WebAssembly.LinkError);
}

// Memory objects exported from a memory64 module retain their address type.
{
    // (module
    //   (memory (export "m") i64 1 3)
    // )
    const module = new WebAssembly.Module(new Uint8Array([
        0x00, 0x61, 0x73, 0x6d, 0x01, 0x00, 0x00, 0x00,
        0x05, 0x04, 0x01, 0x05, 0x01, 0x03,
        0x07, 0x05, 0x01, 0x01, 0x6d, 0x02, 0x00,
    ]));
    const memory = new WebAssembly.Instance(module).exports.m;
    assertSame(1n, memory.grow(1n));
    assertSame(2n, memory.grow(0n));
    assertThrows(() => memory.grow(0), TypeError);
}

// A callback from a start function must preserve the address type of a shared memory.
{
    // (module
    //   (memory (export "memory") i64 1 3 shared)
    //   (func $start
    //     i64.const 0
    //     i32.const 0
    //     memory.atomic.notify
    //     drop)
    //   (start $start))
    const module = new WebAssembly.Module(new Uint8Array([
        0x00, 0x61, 0x73, 0x6d, 0x01, 0x00, 0x00, 0x00,
        0x01, 0x04, 0x01, 0x60, 0x00, 0x00,
        0x03, 0x02, 0x01, 0x00,
        0x05, 0x04, 0x01, 0x07, 0x01, 0x03,
        0x07, 0x0a, 0x01, 0x06, 0x6d, 0x65, 0x6d, 0x6f, 0x72, 0x79, 0x02, 0x00,
        0x08, 0x01, 0x00,
        0x0a, 0x0d, 0x01, 0x0b, 0x00, 0x42, 0x00, 0x41, 0x00, 0xfe, 0x00, 0x02, 0x00, 0x1a, 0x0b,
    ]));
    const memory = new WebAssembly.Instance(module).exports.memory;
    assertSame(1n, memory.grow(0n));
    assertThrows(() => memory.grow(0), TypeError);
}

// Structured cloning preserves a shared memory's address type and buffer identity.
{
    const memory = new WebAssembly.Memory({initial: 1n, maximum: 3n, shared: true, address: 'i64'});
    const view = new Uint32Array(memory.toResizableBuffer());
    const worker = new Worker(`
        onmessage = function (event) {
            const {memory, view} = event.data;
            if (view.buffer !== memory.buffer || memory.grow(0n) !== 1n) {
                throw new Error("cloned memory64 state was not preserved");
            }
            postMessage("done");
        };
    `, {type: 'string'});
    worker.postMessage({memory, view});
    assertSame('done', worker.getMessage());
    worker.terminate();
}
