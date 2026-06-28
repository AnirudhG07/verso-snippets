// Click-to-panel infoview for `lean-snippet --slide`.
//
// Instead of hover tooltips, the reader clicks a name, tactic, or message and
// its details appear in the side panel. This avoids hover boxes popping up over
// content during a presentation, and works well when the snippet is embedded.
//
// It reads the same data the normal hover mode emits:
//   * `_versoDocsJson[id]`        — docs/type for a `.token[data-verso-hover]`
//   * `.tactic > .tactic-state`   — the goal state inside a `.tactic`
//   * `.has-info .hover-info`     — a diagnostic message (if any survive)
//   * `.token[data-binding]`      — used to highlight every occurrence of a binder
window.addEventListener("load", () => {
  const panel = document.querySelector(".info-panel");
  if (!panel) return;
  const docs = typeof _versoDocsJson !== "undefined" ? _versoDocsJson : {};
  const EMPTY =
    '<div class="info-panel-empty">Click a name, tactic, or message to see its details here.</div>';

  const setPanel = (html) => {
    if (!html || !html.trim()) {
      panel.innerHTML = EMPTY;
      return;
    }
    panel.innerHTML = '<div class="hl lean">' + html + "</div>";
    // Render docstring markdown (e.g. `Foo` -> inline code) like the hover mode.
    panel.querySelectorAll("code.docstring").forEach((d) => {
      if (typeof marked !== "undefined") {
        const div = document.createElement("div");
        div.className = "docstring-rendered";
        div.innerHTML = marked.parse(d.textContent);
        d.replaceWith(div);
      }
    });
  };
  setPanel(null);

  let selected = null;
  const select = (el) => {
    if (selected) selected.classList.remove("panel-selected");
    selected = el;
    if (el) el.classList.add("panel-selected");
  };

  // Highlight every occurrence of the clicked binder (same context + binding).
  let lit = [];
  const litBinding = (block, binding) => {
    lit.forEach((t) => t.classList.remove("binding-hl"));
    lit = [];
    if (!binding) return;
    const ctx = block.dataset.leanContext;
    document.querySelectorAll("code.hl.lean").forEach((ex) => {
      if (ex.dataset.leanContext !== ctx) return;
      ex.querySelectorAll(
        '.token[data-binding="' + CSS.escape(binding) + '"]'
      ).forEach((t) => {
        t.classList.add("binding-hl");
        lit.push(t);
      });
    });
  };

  // The HTML to show in the panel for a clicked element.
  const infoHtml = (el) => {
    if (el.classList.contains("tactic")) {
      const st = el.querySelector(":scope > .tactic-state");
      return st ? st.outerHTML : ""; // keep the .tactic-state wrapper for layout
    }
    if (el.classList.contains("has-info")) {
      const info = el.querySelector(":scope > .hover-container > .hover-info");
      return info ? info.innerHTML : "";
    }
    // A name token: show "Name : Type" (name keeps its colour) then the docs.
    const doc = docs[el.getAttribute("data-verso-hover")] || "";
    const wrap = document.createElement("div");
    wrap.innerHTML = doc;
    const sig = wrap.querySelector("code:not(.docstring)");
    const name = el.textContent.trim();
    if (sig && name && !sig.textContent.trim().startsWith(name)) {
      sig.innerHTML = el.outerHTML + " : " + sig.innerHTML;
    }
    return wrap.innerHTML;
  };

  // Clicking cycles outward→inward: a tactic's goal first, then the token under
  // the cursor. Clicking the same spot again steps to the next inner element.
  let lastInner = null;
  let cycleIdx = 0;
  document.querySelectorAll("code.hl.lean.block").forEach((block) => {
    block.addEventListener("click", (event) => {
      const chain = [];
      let el = event.target;
      while (el && el !== block) {
        if (el.matches && el.matches(".tactic, .has-info, .token[data-verso-hover]"))
          chain.push(el);
        el = el.parentElement;
      }
      const tok = event.target.closest(".token[data-binding]");
      litBinding(block, tok && tok.dataset.binding);
      if (!chain.length) return;
      chain.reverse(); // outermost (tactic) first, innermost (token) last
      const inner = chain[chain.length - 1];
      if (inner === lastInner) cycleIdx = (cycleIdx + 1) % chain.length;
      else {
        lastInner = inner;
        cycleIdx = 0;
      }
      const sel = chain[cycleIdx];
      event.preventDefault();
      select(sel);
      setPanel(infoHtml(sel));
    });
  });
});
