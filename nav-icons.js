const navIconFiles = ["home", "food", "recipe", "pet", "settings"];

const applyNavigationIconAssets = () => {
  const nav = document.querySelector(".bottom-nav");
  if (!nav) return;
  [...nav.querySelectorAll("button")].forEach((button, index) => {
    const inlineIcon = button.querySelector("svg.nav-icon");
    const file = navIconFiles[index];
    if (!inlineIcon || !file) return;
    const icon = document.createElement("img");
    icon.className = `nav-icon nav-icon-${file === "recipe" ? "recipes" : file}`;
    icon.src = `/icons/${file}.svg`;
    icon.alt = "";
    icon.setAttribute("aria-hidden", "true");
    inlineIcon.replaceWith(icon);
  });
};

const navIconObserver = new MutationObserver(applyNavigationIconAssets);
navIconObserver.observe(document.body, { childList: true, subtree: true });
applyNavigationIconAssets();
