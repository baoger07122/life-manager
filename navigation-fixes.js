const secondaryPages = [
  {
    id: "food-detail",
    target: "food",
    label: "食品",
    marker: ".detail-hero",
    removeActions: ["返回列表"]
  },
  {
    id: "reminders",
    target: "home",
    label: "首页",
    marker: ".reminder-list",
    removeActions: []
  },
  {
    id: "prep",
    target: "recipes",
    label: "菜谱",
    marker: ".prep-head",
    removeActions: ["返回"]
  }
];

const getPageTarget = (content) => secondaryPages.find((page) => content.querySelector(page.marker)) || null;

const findNavigationButton = (label) => [...document.querySelectorAll(".bottom-nav button")]
  .find((button) => button.textContent?.trim().includes(label));

const goBackTo = (page) => {
  const navigationButton = findNavigationButton(page.label);
  if (navigationButton) {
    navigationButton.click();
    return;
  }
  window.location.hash = page.target;
};

const addBackButton = (header, page) => {
  header.classList.add("has-back");

  let backButton = header.querySelector(".home-os-back");
  if (!backButton) {
    backButton = document.createElement("button");
    backButton.type = "button";
    backButton.className = "home-os-back";
    backButton.innerHTML = '<span aria-hidden="true">‹</span><span>返回</span>';
    header.prepend(backButton);
  }

  backButton.setAttribute("aria-label", `返回${page.label}`);
  backButton.dataset.target = page.target;
  backButton.onclick = () => goBackTo(page);

  [...header.querySelectorAll(".btn")]
    .filter((button) => page.removeActions.includes(button.textContent?.trim()))
    .forEach((button) => button.remove());
};

const removeHomeViewSetting = () => {
  [...document.querySelectorAll(".settings-block")].forEach((block) => {
    const title = [...block.children].find((child) => child.tagName === "B");
    if (title?.textContent?.trim() !== "首页视图") return;

    const section = block.closest(".settings-section");
    if (section?.querySelector("h2")?.textContent?.trim() === "外观") {
      section.remove();
    } else {
      block.remove();
    }
  });
};

const refreshNavigationFixes = () => {
  const content = document.querySelector(".app-content");
  if (!content) return;

  removeHomeViewSetting();

  const header = content.querySelector(".page-header");
  const headerTitle = header?.querySelector("h1")?.textContent?.trim();
  header?.classList.toggle("settings-page-header", headerTitle === "设置");
  const page = getPageTarget(content);
  if (!header) return;

  if (page) {
    addBackButton(header, page);
  } else {
    header.classList.remove("has-back");
    header.querySelector(".home-os-back")?.remove();
  }
};

let refreshScheduled = false;
const scheduleRefresh = () => {
  if (refreshScheduled) return;
  refreshScheduled = true;
  window.setTimeout(() => {
    refreshScheduled = false;
    refreshNavigationFixes();
  }, 0);
};

const observer = new MutationObserver(scheduleRefresh);
observer.observe(document.body, { childList: true, subtree: true });
scheduleRefresh();
