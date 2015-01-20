function syncRequest(r, q, h) {
    if (r === 'query') { console.log(q); }
    $.ajax({
        type: 'POST',
        url: r,
        data: {query : q},
        async: false,
        success: function(response) {
            //console.log("response", response);
            h(response);
        }
    });
}

function syncQuery(q, h)       { syncRequest('query', q, h); }

/*
function syncQueryUndo(q, h)   { syncRequest('queryundo', q, h); }
function syncUndo(h)           { syncRequest('undo', undefined, h); }
function syncParse(q, h)       { syncRequest('parse', q, h); }
function syncParseEval(q, h)   { syncRequest('parseEval', q, h); }
function syncParseCheck(q, h)  { syncRequest('parseCheck', q, h); }
function syncListLectures(h)   { syncRequest("listLectures", "", h); }
function syncLoadLecture(q, h) { syncRequest("loadLecture", q, h); }
function syncLog(s) {
    var time = "[" + new Date().toLocaleString() + "] ";
    syncRequest("log", time + s, function() {});
}

function syncStatus() {
    var result;
    syncRequest("status", "", function(response) {
        var msg = response.rResponse.contents[0];
        var r = msg.match("^\\\((.*),(.*),(.*),\"(.*)\",\"(.*)\"\\\)$");
        result = {
            "sections": r[1],
            "current": (r[2] === "Nothing") ? null : r[2].substring(5).replace(/"/g, ""),
            "currents": r[3],
            "label": + r[4],
            "proving": (r[5] === "1"),
            "response": response,
        };
    });
    return result;
}

function syncCurrentLabel() {
    return syncStatus().label;
}

function syncResetCoq() {
    var label = syncCurrentLabel();
    if (label > 0) {
        syncRequest("rewind", label - 1, function(){});
        syncQuery("Require Import Unicode.Utf8 Bool Arith List.", function(){});
        syncQuery("Open ListNotations.", function(){});
    }
}

function syncResetCoqNoImports() {
    var label = syncCurrentLabel();
    if (label > 0) {
        syncRequest("rewind", label - 1, function(){});
    }
}
*/

var processingAsync = false;
var asyncRequests = [];

function processAsyncRequests() {
    if (processingAsync || _(asyncRequests).isEmpty()) { return; }
    var request = asyncRequests.shift();
    var r = request.url;
    var q = request.query;
    var h = request.callback;
    if (r === 'query') { console.log(q); }
    processingAsync = true;
    var beforeTime = Date.now();
    $.ajax({
        type: 'POST',
        url: r,
        data: {query : q},
        async: true,
        success: function(response) {
            var afterTime = Date.now();
            processingAsync = false;
            processAsyncRequests();
            h(response);
        }
    });
}

function asyncRequest(r, q, h) {
    asyncRequests.push({
        "url": r,
        "query": q,
        "callback": h,
    });
    processAsyncRequests();
}

function asyncQuery(q, h)        { asyncRequest('query', q, h); }
function asyncQueryAndUndo(q, h) { asyncRequest('queryundo', q, h); }
function asyncUndo(h)            { asyncRequest('undo', undefined, h); }
function asyncLog(s) {
    var time = "[" + new Date().toLocaleString() + "] ";
    asyncRequest("log", time + s, function() {});
}

function asyncStatus(callback) {
    asyncRequest("status", "", function(response) {
        var msg = response.rResponse.contents[0];
        var r = msg.match("^\\\((.*),(.*),(.*),\"(.*)\",\"(.*)\"\\\)$");
        var result = {
            "sections": r[1],
            "current": (r[2] === "Nothing") ? null : r[2].substring(5).replace(/"/g, ""),
            "currents": r[3],
            "label": + r[4],
            "proving": (r[5] === "1"),
            "response": response,
        };
        callback(result);
    });
}

function asyncCurrentLabel(callback) {
    asyncStatus(function(result) {
        callback(result.label);
    });
}

function asyncResetCoq(callback) {
    asyncCurrentLabel(function(label) {
        if (label > 0) {
            asyncRequest("rewind", label - 1, function(){
                asyncQuery("Require Import Unicode.Utf8 Bool Arith List.", function(){
                    asyncQuery("Open ListNotations.", callback);
                });
            });
        } else {
            callback();
        }
    });
}

function asyncResetCoqNoImports(callback) {
    asyncCurrentLabel(function(label) {
        if (label > 0) {
            asyncRequest("rewind", label - 1, callback);
        } else {
            callback();
        }
    });
}
