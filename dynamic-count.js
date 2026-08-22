const readFoodCount = () => {
  try {
    const state = JSON.parse(window.localStorage.getItem("home-os-v1") || "null");
    return Array.isArray(state?.foods) ? state.foods.length : 0;
  } catch {
    return 0;
  }
};

const updateOverviewCount = () => {
  const stat = [...document.querySelectorAll(".overview-stat")]
    .find((item) => item.querySelector("small")?.textContent?.trim() === "全部物品");
  const value = stat?.querySelector("b");
  if (!value) return;
  const nextValue = String(readFoodCount());
  if (value.textContent !== nextValue) value.textContent = nextValue;
};

const countObserver = new MutationObserver(() => {
  window.setTimeout(updateOverviewCount, 0);
});
countObserver.observe(document.body, { childList: true, subtree: true });
updateOverviewCount();
