const navIconFiles = ["home", "food", "recipe", "pet", "settings"];
const iconCache = new Map();
const pendingButtons = new WeakSet();

const loadInlineIcon = (file) => {
  if (!iconCache.has(file)) {
    const request = fetch(`/icons/${file}.svg`, { cache: "force-cache" })
      .then((response) => {
        if (!response.ok) throw new Error(`navigation icon unavailable: ${file}`);
        return response.text();
      })
      .then((markup) => {
        const parsed = new DOMParser().parseFromString(markup, "image/svg+xml");
        const source = parsed.documentElement;
        if (!source || source.nodeName.toLowerCase() !== "svg") throw new Error(`invalid navigation icon: ${file}`);

        const icon = document.importNode(source, true);
        icon.classList.add("nav-icon", `nav-icon-${file === "recipe" ? "recipes" : file}`);
        icon.dataset.navAsset = file;
        icon.setAttribute("aria-hidden", "true");
        icon.removeAttribute("width");
        icon.removeAttribute("height");
        return icon;
      });
    iconCache.set(file, request);
  }
  return iconCache.get(file);
};

const applyNavigationIconAssets = () => {
  const nav = document.querySelector(".bottom-nav");
  if (!nav) return;

  [...nav.querySelectorAll("button")].forEach((button, index) => {
    const inlineIcon = button.querySelector("svg.nav-icon");
    const file = navIconFiles[index];
    if (!inlineIcon || !file || inlineIcon.dataset.navAsset === file || pendingButtons.has(button)) return;

    pendingButtons.add(button);
    loadInlineIcon(file)
      .then((icon) => {
        if (button.isConnected) inlineIcon.replaceWith(icon);
      })
      .catch(() => undefined)
      .finally(() => pendingButtons.delete(button));
  });
};

const navIconObserver = new MutationObserver(applyNavigationIconAssets);
navIconObserver.observe(document.body, { childList: true, subtree: true });
applyNavigationIconAssets();
