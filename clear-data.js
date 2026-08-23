const EMPTY_HOME_STATE = {
  foods: [],
  recipes: [],
  plans: [],
  prepChecks: [],
  petItems: [],
  activities: [],
  settings: {
    threshold: 15,
    locations: ["冷藏区", "冷冻区", "常温区"],
    view: "list"
  }
};

const clearLocalData = () => {
  const confirmed = window.confirm("确定清空当前设备上的 Home OS 数据吗？此操作不会影响线上版本，但会删除本机食品、菜谱、计划和宠物数据。");
  if (!confirmed) return;

  window.localStorage.setItem("home-os-v1", JSON.stringify(EMPTY_HOME_STATE));
  const hash = window.location.hash || "#home";
  window.location.replace(`${window.location.pathname}?v=8.23.14&refresh=${Date.now()}${hash}`);
};

const ensureClearDataRow = () => {
  if (document.querySelector("[data-homeos-clear-local]")) return;
  const restoreRow = [...document.querySelectorAll(".settings-row")]
    .find((row) => row.textContent?.includes("恢复数据"));
  if (!restoreRow) return;

  const row = document.createElement("button");
  row.type = "button";
  row.className = "settings-row settings-link";
  row.dataset.homeosClearLocal = "true";
  row.innerHTML = "<span><b>清空本地数据</b><small>仅清空当前设备，不影响线上版本</small></span><i>›</i>";
  row.addEventListener("click", clearLocalData);
  restoreRow.insertAdjacentElement("afterend", row);
};

const clearDataObserver = new MutationObserver(ensureClearDataRow);
clearDataObserver.observe(document.body, { childList: true, subtree: true });
ensureClearDataRow();
