// mded preview renderer.
//
// Runs as a user script in an isolated WKContentWorld, after marked.min.js and
// highlight.min.js. Page JavaScript is disabled, so nothing in a document can
// execute; only this world can. The unit tests also load this file under
// JavaScriptCore, so everything that touches the DOM is guarded.
(function (root) {
  'use strict';

  var options = {
    // Treat _ as a literal everywhere; only *…* and **…** mark emphasis, so
    // identifiers like __init__ aren't bolded. (A preference in the app.)
    literalUnderscores: true
  };

  root.mdedSetOptions = function (changes) {
    Object.keys(changes || {}).forEach(function (key) { options[key] = changes[key]; });
  };

  // Declining `_` runs in emStrong (instead of adding an inline extension with a
  // `start` hook) leaves marked's text tokenizer untouched, so autolinks such as
  // first_last@example.com still link as a whole.
  marked.use({
    tokenizer: {
      emStrong: function (src) {
        if (options.literalUnderscores && src.charAt(0) === '_') return undefined; // falls through to text
        return false; // defer to marked's own tokenizer
      }
    }
  });

  // GitHub-style heading ids so [links](#section) and tables of contents work.
  var usedSlugs = Object.create(null);
  var entities = { amp: '&', lt: '<', gt: '>', quot: '"', '#39': "'" };

  function plainText(html) {
    return html
      .replace(/<[^>]*>/g, '')
      .replace(/&(#x[0-9a-f]+|#\d+|amp|lt|gt|quot);/gi, function (m, e) {
        if (e.charAt(0) === '#') {
          var code = e.charAt(1).toLowerCase() === 'x' ? parseInt(e.slice(2), 16) : parseInt(e.slice(1), 10);
          return isNaN(code) ? m : String.fromCodePoint(code);
        }
        return entities[e.toLowerCase()] || m;
      });
  }

  function slugify(text) {
    var base = text.toLowerCase().trim()
      .replace(/[^\p{L}\p{M}\p{N}\p{Pc}\- ]/gu, '')
      .replace(/ /g, '-');
    var slug = base;
    for (var i = 1; usedSlugs[slug]; i++) slug = base + '-' + i;
    usedSlugs[slug] = true;
    return slug;
  }

  function escapeAttr(s) {
    return s.replace(/&/g, '&amp;').replace(/"/g, '&quot;').replace(/</g, '&lt;');
  }

  marked.use({
    renderer: {
      heading: function (token) {
        var inner = this.parser.parseInline(token.tokens);
        var id = slugify(plainText(inner));
        return '<h' + token.depth + ' id="' + escapeAttr(id) + '">' + inner + '</h' + token.depth + '>\n';
      }
    }
  });

  // Parses into top-level blocks, each with the 0-based source line it starts
  // on, which the preview stamps as data-line for line-accurate scroll sync.
  function parseBlocks(text) {
    usedSlugs = Object.create(null);
    var src = String(text || '').replace(/\r\n?/g, '\n');
    var tokens = marked.lexer(src, marked.defaults);
    var blocks = [];
    var position = 0;
    var line = 0;
    function advanceTo(offset) {
      for (var i = position; i < offset; i++) if (src.charCodeAt(i) === 10) line++;
      position = offset;
    }
    tokens.forEach(function (token) {
      // Locate each token in the source rather than summing raw lengths:
      // marked drops some tokens (link reference definitions) entirely.
      var at = token.raw ? src.indexOf(token.raw, position) : -1;
      if (at >= 0) advanceTo(at);
      var start = line;
      if (at >= 0) advanceTo(at + token.raw.length);
      if (token.type === 'space') return;
      var single = [token];
      single.links = tokens.links;
      blocks.push({ line: start, html: marked.parser(single, marked.defaults) });
    });
    advanceTo(src.length);
    return { blocks: blocks, lineCount: line + 1 };
  }

  root.mdedParseBlocks = parseBlocks;
  root.mdedParse = function (text) {
    return parseBlocks(text).blocks.map(function (b) { return b.html; }).join('');
  };

  if (typeof document === 'undefined') return;

  // ---- Syntax highlighting -------------------------------------------------
  // Cached by language + source so unchanged blocks aren't re-highlighted (and
  // re-auto-detected, which is expensive) on every keystroke.
  var highlightCache = new Map();

  function highlight(container) {
    container.querySelectorAll('pre code').forEach(function (el) {
      var lang = (/(?:^|\s)language-([\w+#.-]+)/.exec(el.className) || [])[1];
      if (lang && !hljs.getLanguage(lang)) return; // unknown language (e.g. mermaid): leave plain
      var source = el.textContent;
      var key = (lang || '') + '\u0000' + source;
      var hit = highlightCache.get(key);
      if (!hit) {
        var result = lang
          ? hljs.highlight(source, { language: lang, ignoreIllegals: true })
          : hljs.highlightAuto(source);
        hit = { html: result.value, language: result.language };
        if (highlightCache.size > 500) highlightCache.clear();
        highlightCache.set(key, hit);
      }
      el.innerHTML = hit.html;
      el.classList.add('hljs');
      if (hit.language) el.classList.add('language-' + hit.language);
    });
  }

  // ---- DOM morphing --------------------------------------------------------
  // Re-rendering by replacing innerHTML reloads every image and iframe and
  // collapses open <details> on each keystroke. Instead, patch the live tree:
  // unchanged nodes are kept, and edited ones are updated in place.
  var LOOKAHEAD = 8;

  // isEqualNode, except that (a) a top-level block's data-line is ignored (an
  // edit above it shifts it without changing the block), and (b) a <details>
  // the reader has opened or closed still matches its freshly rendered twin.
  function equivalent(a, b) {
    if (a.nodeType !== b.nodeType || a.nodeName !== b.nodeName) return false;
    if (a.nodeType !== Node.ELEMENT_NODE) return a.nodeValue === b.nodeValue;
    var line = b.getAttribute('data-line');
    if (line !== null && a.hasAttribute('data-line')) b.setAttribute('data-line', a.getAttribute('data-line'));
    var same = a.isEqualNode(b) ||
      ((a.nodeName === 'DETAILS' || a.querySelector('details') !== null) && sameIgnoringDetailsOpen(a, b));
    if (line !== null) b.setAttribute('data-line', line);
    return same;
  }

  function sameIgnoringDetailsOpen(a, b) {
    if (a.nodeType !== b.nodeType || a.nodeName !== b.nodeName) return false;
    if (a.nodeType !== Node.ELEMENT_NODE) return a.nodeValue === b.nodeValue;
    var skip = a.nodeName === 'DETAILS' ? 'open' : null;
    function attrs(el) {
      return Array.prototype.filter.call(el.attributes, function (x) { return x.name !== skip; })
        .map(function (x) { return x.name + '=' + x.value; }).sort().join('\u0000');
    }
    if (attrs(a) !== attrs(b) || a.childNodes.length !== b.childNodes.length) return false;
    for (var i = 0; i < a.childNodes.length; i++) {
      if (!sameIgnoringDetailsOpen(a.childNodes[i], b.childNodes[i])) return false;
    }
    return true;
  }

  function findAhead(start, node) {
    for (var n = start, i = 0; n && i < LOOKAHEAD; n = n.nextSibling, i++) {
      if (equivalent(n, node)) return n;
    }
    return null;
  }

  // A kept node takes the new render's source line.
  function adoptLine(kept, rendered) {
    if (rendered.nodeType === Node.ELEMENT_NODE && rendered.hasAttribute('data-line') &&
        kept.getAttribute('data-line') !== rendered.getAttribute('data-line')) {
      kept.setAttribute('data-line', rendered.getAttribute('data-line'));
    }
  }

  function syncAttributes(from, to) {
    var keepOpen = from.nodeName === 'DETAILS'; // user-toggled state wins
    Array.prototype.slice.call(from.attributes).forEach(function (a) {
      if (!to.hasAttribute(a.name) && !(keepOpen && a.name === 'open')) from.removeAttribute(a.name);
    });
    Array.prototype.forEach.call(to.attributes, function (a) {
      if (keepOpen && a.name === 'open') return;
      if (from.getAttribute(a.name) !== a.value) from.setAttribute(a.name, a.value);
    });
  }

  function morphChildren(from, to) {
    var f = from.firstChild;
    var t = to.firstChild;
    while (t) {
      var tNext = t.nextSibling;
      if (!f) {
        from.appendChild(t);
      } else if (equivalent(f, t)) {
        adoptLine(f, t);
        f = f.nextSibling;
      } else if (findAhead(tNext, f)) {
        from.insertBefore(t, f);                 // t was inserted before f
      } else {
        var match = findAhead(f.nextSibling, t);
        if (match) {                             // nodes before `match` were deleted
          while (f !== match) { var gone = f; f = f.nextSibling; from.removeChild(gone); }
          adoptLine(f, t);
          f = f.nextSibling;
        } else if (f.nodeType === t.nodeType && f.nodeName === t.nodeName) {
          if (f.nodeType === Node.ELEMENT_NODE) {
            syncAttributes(f, t);
            morphChildren(f, t);
          } else if (f.nodeValue !== t.nodeValue) {
            f.nodeValue = t.nodeValue;
          }
          f = f.nextSibling;
        } else {
          var replaced = f;
          f = f.nextSibling;
          from.replaceChild(t, replaced);
        }
      }
      t = tNext;
    }
    while (f) { var extra = f; f = f.nextSibling; from.removeChild(extra); }
  }

  // ---- Scroll sync ---------------------------------------------------------
  // Positions are exchanged as source lines (fractional: 12.5 is halfway
  // through line 12's block), interpolated between the tops of the blocks
  // stamped with data-line. Images and code blocks no longer cause drift.
  var content = document.getElementById('content');
  var lineCount = 1;
  var programmaticTop = null; // where the app last scrolled us; that echo isn't reported back
  var quietUntil = 0;         // layout settling after a render isn't a user scroll

  function maxScroll() {
    var d = document.documentElement;
    return Math.max(0, d.scrollHeight - d.clientHeight);
  }

  function blockTop(el) {
    return el.getBoundingClientRect().top + window.scrollY;
  }

  // Anchor points (line, y) bracketing a position. `pick(i)` is the value
  // binary-searched on for block i; `target` is what we're looking for.
  function bracket(pick, target) {
    var blocks = content.children;
    var lo = 0, hi = blocks.length - 1, idx = -1;
    while (lo <= hi) {
      var mid = (lo + hi) >> 1;
      if (pick(blocks[mid]) <= target) { idx = mid; lo = mid + 1; } else { hi = mid - 1; }
    }
    function point(i) {
      if (i < 0) return { line: 0, y: 0 };
      if (i >= blocks.length) return { line: lineCount, y: document.documentElement.scrollHeight };
      return { line: Number(blocks[i].getAttribute('data-line')) || 0, y: blockTop(blocks[i]) };
    }
    return [point(idx), point(idx + 1)];
  }

  function lineAtScrollTop(y) {
    var p = bracket(blockTop, y);
    if (p[1].y <= p[0].y) return p[0].line;
    return p[0].line + (p[1].line - p[0].line) * (y - p[0].y) / (p[1].y - p[0].y);
  }

  function scrollTopForLine(line) {
    var p = bracket(function (el) { return Number(el.getAttribute('data-line')) || 0; }, line);
    if (p[1].line <= p[0].line) return p[0].y;
    return p[0].y + (p[1].y - p[0].y) * (line - p[0].line) / (p[1].line - p[0].line);
  }

  function postScroll(position) {
    var handlers = window.webkit && window.webkit.messageHandlers;
    if (handlers && handlers.previewScroll) handlers.previewScroll.postMessage(position);
  }

  var ticking = false;
  window.addEventListener('scroll', function () {
    if (ticking) return;
    ticking = true;
    requestAnimationFrame(function () {
      ticking = false;
      var top = document.documentElement.scrollTop;
      var echo = programmaticTop !== null && Math.abs(top - programmaticTop) <= 1;
      programmaticTop = null;
      if (echo || performance.now() < quietUntil) return;
      var max = maxScroll();
      postScroll({ line: lineAtScrollTop(top), atEnd: max > 0 && top >= max - 1 });
    });
  }, { passive: true });

  // ---- Entry points called from Swift (callAsyncJavaScript, this world) ----
  root.render = function (text) {
    var parsed = parseBlocks(text);
    lineCount = parsed.lineCount;
    var template = document.createElement('template'); // inert: nothing loads until adopted
    parsed.blocks.forEach(function (block) {
      var piece = document.createElement('template');
      piece.innerHTML = block.html;
      Array.prototype.forEach.call(piece.content.children, function (el) {
        el.setAttribute('data-line', block.line);
      });
      template.content.appendChild(piece.content);
    });
    highlight(template.content);
    // Explicit file: URLs can't load into this page; route them through the
    // app's mded-file: handler like relative paths.
    template.content.querySelectorAll(
      'img[src^="file:" i], video[src^="file:" i], audio[src^="file:" i], source[src^="file:" i]'
    ).forEach(function (el) {
      el.setAttribute('src', 'mded-file:' + el.getAttribute('src').slice(5));
    });
    quietUntil = performance.now() + 150;
    morphChildren(content, template.content);
  };

  root.setEvening = function (on) {
    document.body.classList.toggle('evening-mode', !!on);
  };

  root.scrollToLine = function (line, atEnd) {
    var top = Math.round(atEnd ? maxScroll() : Math.min(maxScroll(), Math.max(0, scrollTopForLine(line))));
    programmaticTop = top;
    document.documentElement.scrollTop = top;
  };

  root.scrollToAnchor = function (id) {
    var el = document.getElementById(id) ||
      document.getElementById(id.toLowerCase()) ||
      document.getElementsByName(id)[0];
    if (el) el.scrollIntoView({ block: 'start' });
    return !!el;
  };

  // Resolves once every image has loaded or failed, so printing and export see
  // the final layout. (Not requestAnimationFrame: the exporter's web view is
  // never on screen, so it never gets a frame.)
  root.whenImagesLoaded = async function () {
    await Promise.all(Array.prototype.map.call(document.images, function (img) {
      if (img.complete) return null;
      return new Promise(function (resolve) {
        img.addEventListener('load', resolve, { once: true });
        img.addEventListener('error', resolve, { once: true });
      });
    }));
    await new Promise(function (resolve) { setTimeout(resolve, 0); });
  };

  root.selectedText = function () {
    return String(window.getSelection() || '');
  };

  root.clearSelection = function () {
    var selection = window.getSelection();
    if (selection) selection.removeAllRanges();
  };

  // The rendered document as standalone HTML: local images inlined as data
  // URLs, and anything that could run script removed, so the exported file is
  // as inert as the preview.
  root.exportBodyHTML = async function () {
    var clone = content.cloneNode(true);
    clone.querySelectorAll('script, iframe[srcdoc], object, embed').forEach(function (el) { el.remove(); });
    clone.querySelectorAll('*').forEach(function (el) {
      el.removeAttribute('data-line');
      Array.prototype.slice.call(el.attributes).forEach(function (a) {
        if (/^on/i.test(a.name) || /^\s*javascript:/i.test(a.value)) el.removeAttribute(a.name);
      });
    });
    await Promise.all(Array.prototype.map.call(clone.querySelectorAll('img[src]'), async function (img) {
      var url = new URL(img.getAttribute('src'), document.baseURI);
      if (url.protocol !== 'mded-file:') return;
      try {
        var blob = await (await fetch(url.href)).blob();
        var dataURL = await new Promise(function (resolve, reject) {
          var reader = new FileReader();
          reader.onload = function () { resolve(reader.result); };
          reader.onerror = reject;
          reader.readAsDataURL(blob);
        });
        img.setAttribute('src', dataURL);
      } catch (e) {
        // Leave the original path; the image may still resolve next to the file.
      }
    }));
    return clone.innerHTML;
  };
})(typeof globalThis !== 'undefined' ? globalThis : this);
