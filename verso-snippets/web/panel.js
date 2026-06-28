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

  document.querySelectorAll("code.hl.lean.block").forEach((block) => {
    block.addEventListener("click", (event) => {
      const infoEl = event.target.closest(
        ".tactic, .has-info, .token[data-verso-hover]"
      );
      const tok = event.target.closest(".token[data-binding]");
      litBinding(block, tok && tok.dataset.binding);

      if (infoEl && block.contains(infoEl)) {
        let html = "";
        if (infoEl.classList.contains("tactic")) {
          const st = infoEl.querySelector(":scope > .tactic-state");
          html = st ? st.innerHTML : "";
        } else if (infoEl.classList.contains("has-info")) {
          const info = infoEl.querySelector(
            ":scope > .hover-container > .hover-info"
          );
          html = info ? info.innerHTML : "";
        } else {
          html = docs[infoEl.getAttribute("data-verso-hover")] || "";
        }
        event.preventDefault();
        select(infoEl);
        setPanel(html);
      } else {
        select(tok);
      }
    });
  });
});
