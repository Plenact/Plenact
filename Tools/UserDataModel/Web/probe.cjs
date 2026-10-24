/*
 * Plenact User Data Model 1.0 JavaScript schema/JSON conformance probe.
 * Supported model versions: 1.0. Not the web app, storage layer, auth or sync engine.
 * Full date/reference/protocol semantics are independently checked by the Python runner.
 */
'use strict';
const fs = require('node:fs');
const path = require('node:path');
const assert = require('node:assert/strict');
const Ajv2020 = require('ajv/dist/2020');
const addFormats = require('ajv-formats');

/** Parse bounded scalar-valid JSON and reject duplicate keys before using its object model. */
function parseStrictJSON(text) {
    if (Buffer.byteLength(text, 'utf8') > 8388608) throw new Error('input_too_large');
    const value = JSON.parse(text);
    let pos = 0;
    function ws() { while (/\s/.test(text[pos] || '') && pos < text.length) pos++; }
    function string() {
        const start = pos++;
        while (pos < text.length) {
            const char = text[pos++];
            if (char === '\\') pos++;
            else if (char === '"') return JSON.parse(text.slice(start, pos));
        }
        throw new Error('invalid_json');
    }
    function scan(depth) {
        if (depth > 64) throw new Error('json_too_deep');
        ws();
        if (text[pos] === '{') {
            const keys = new Set(); pos++; ws();
            if (text[pos] === '}') { pos++; return; }
            while (true) {
                ws(); const key = string();
                if (keys.has(key)) throw new Error('duplicate_key');
                keys.add(key); ws(); pos++; scan(depth + 1); ws();
                if (text[pos++] === '}') break;
            }
        } else if (text[pos] === '[') {
            pos++; ws();
            if (text[pos] === ']') { pos++; return; }
            while (true) { scan(depth + 1); ws(); if (text[pos++] === ']') break; }
        } else if (text[pos] === '"') string();
        else while (pos < text.length && !/[\s,\]}]/.test(text[pos])) pos++;
    }
    scan(0);
    function scalarCheck(node) {
        if (typeof node === 'number' && (!Number.isFinite(node) || (Number.isInteger(node) && !Number.isSafeInteger(node)))) throw new Error('unsafe_number');
        if (typeof node === 'string') {
            for (let i = 0; i < node.length; i++) {
                const unit = node.charCodeAt(i);
                if (unit >= 0xD800 && unit <= 0xDBFF) {
                    const next = node.charCodeAt(++i);
                    if (!(next >= 0xDC00 && next <= 0xDFFF)) throw new Error('invalid_unicode_scalar');
                } else if (unit >= 0xDC00 && unit <= 0xDFFF) throw new Error('invalid_unicode_scalar');
            }
        } else if (Array.isArray(node)) node.forEach(scalarCheck);
        else if (node !== null && typeof node === 'object') for (const [key, child] of Object.entries(node)) { scalarCheck(key); scalarCheck(child); }
    }
    scalarCheck(value);
    return value;
}

/** Check strict parser boundaries independently of a schema, using synthetic strings only. */
function parserChecks() {
    for (const input of ['{"a":1,"a":2}', '{"a":1,"\\u0061":2}', '{"n":1e999}', '{"n":9007199254740993}', '{"x":"\\uD800"}']) {
        assert.throws(() => parseStrictJSON(input));
    }
    assert.deepEqual(parseStrictJSON('{"value":"emoji 🌿 and a quote \\\"","a":[false,null]}'), {value:'emoji 🌿 and a quote "',a:[false,null]});
}

/** Validate all structural expectations, then emit complete valid JSON for independent revalidation. */
function main() {
    assert.equal(process.argv.length, 4, 'Expected contract folder and temporary output folder.');
    parserChecks();
    const root = path.resolve(process.argv[2]);
    const output = path.resolve(process.argv[3]);
    assert.notEqual(root, output);
    assert.ok(!output.startsWith(root + path.sep), 'Output must be outside the contract source.');
    const manifest = parseStrictJSON(fs.readFileSync(path.join(root,'Fixtures/manifest.json'),'utf8'));
    const ajv = new Ajv2020({strict:false, allErrors:true, validateFormats:true});
    addFormats(ajv);
    const schemaFiles = fs.readdirSync(root).filter(name => name.endsWith('.schema.json'));
    for (const name of schemaFiles) ajv.addSchema(parseStrictJSON(fs.readFileSync(path.join(root,name),'utf8')));
    fs.mkdirSync(output,{recursive:true});
    let count = 0;
    for (const fixture of manifest.cases) {
        assert.equal(path.basename(fixture.file),fixture.file);
        let value, accepted = false;
        try {
            value = parseStrictJSON(fs.readFileSync(path.join(root,'Fixtures',fixture.file),'utf8'));
            const schema = parseStrictJSON(fs.readFileSync(path.join(root,fixture.schema),'utf8'));
            accepted = ajv.validate(schema.$id,value);
        } catch (error) {
            if (fixture.valid) throw error;
        }
        assert.equal(Boolean(accepted),fixture.structurally_valid,fixture.name + ': structural outcome mismatch');
        if (!fixture.valid) continue;
        const encoded = JSON.stringify(value,null,2)+'\n';
        assert.deepEqual(parseStrictJSON(encoded),value);
        fs.writeFileSync(path.join(output,fixture.file),encoded);
        count++;
    }
    console.log(`JavaScript checked ${schemaFiles.length} schemas/${manifest.cases.length} structural expectations and emitted ${count} valid round trips.`);
}

if (require.main === module) main();
module.exports = {parseStrictJSON};
