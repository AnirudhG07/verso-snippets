// Drives the header "View" dropdown: Hover / Infoview / Literate.
// All renderings are embedded; we just flip body classes — no regeneration.
window.addEventListener("load", () => {
  const cbs = Array.from(document.querySelectorAll(".mode-cb"));
  if (!cbs.length) return;

  const apply = () => {
    const on = {};
    cbs.forEach((c) => (on[c.value] = c.checked));
    document.body.classList.toggle("mode-hover", !!on.hover);
    document.body.classList.toggle("slide", !!on.slide);
    document.body.classList.toggle("slide-click", !!on.slide && !on.hover);
    document.body.classList.toggle("slide-both", !!on.slide && !!on.hover);
    document.body.classList.toggle("lit-view", !!on.literate);
  };
  cbs.forEach((c) => c.addEventListener("change", apply));
  apply();

  // Close the dropdown when clicking outside it.
  document.addEventListener("click", (e) => {
    const d = document.querySelector("details.mode-switch");
    if (d && d.open && !d.contains(e.target)) d.removeAttribute("open");
  });
});
