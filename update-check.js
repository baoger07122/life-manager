const APP_VERSION = "v1.3.4";
const APP_RELEASE = "个人管家 v1.3.4 - 底部导航安全区间距优化";

const compareVersions = (left, right) => {
  const parse = (value) => value.replace(/^v/i, "").split(".").map((part) => Number.parseInt(part, 10) || 0);
  const a = parse(left);
  const b = parse(right);
  for (let index = 0; index < 3; index += 1) {
    if ((a[index] || 0) !== (b[index] || 0)) return (a[index] || 0) > (b[index] || 0) ? 1 : -1;
  }
  return 0;
};

const setStatus = (card, message) => {
  const status = card.querySelector("[data-update-status]");
  if (status) status.textContent = message;
};

const checkForUpdates = async (event) => {
  const button = event.currentTarget;
  const card = button.closest("[data-homeos-update-card]");
  button.disabled = true;
  setStatus(card, "正在检查最新版本…");
  try {
    const response = await fetch(`/version.json?ts=${Date.now()}`, { cache: "no-store" });
    if (!response.ok) throw new Error("version manifest unavailable");
    const remote = await response.json();
    if (remote.version && compareVersions(remote.version, APP_VERSION) > 0) {
      setStatus(card, `发现 ${remote.version}，正在更新…`);
      if ("serviceWorker" in navigator) {
        const registrations = await navigator.serviceWorker.getRegistrations();
        await Promise.all(registrations.map((registration) => registration.update().catch(() => undefined)));
      }
      const hash = window.location.hash || "#settings";
      window.location.replace(`${window.location.pathname}?v=${encodeURIComponent(remote.version)}&refresh=${Date.now()}${hash}`);
      return;
    }
    setStatus(card, `已是最新版本 · ${APP_VERSION}`);
  } catch {
    setStatus(card, "暂时无法检查，请稍后重试");
  } finally {
    button.disabled = false;
  }
};

const ensureUpdateCard = () => {
  const heading = [...document.querySelectorAll("h1")].find((item) => item.textContent?.trim() === "设置");
  const content = heading?.closest(".app-content");
  if (!content || content.querySelector("[data-homeos-update-card]")) return;

  const card = document.createElement("section");
  card.className = "card settings-section";
  card.dataset.homeosUpdateCard = "true";
  card.innerHTML = `<h2>版本与更新</h2><div class="update-version-row"><div><b>${APP_VERSION}</b><small>${APP_RELEASE}</small></div><button class="btn primary" type="button">检查更新</button></div><p class="update-status" data-update-status>手动检查后会加载最新版本，数据仍保存在本机。</p>`;
  card.querySelector("button")?.addEventListener("click", checkForUpdates);
  const about = content.querySelector(".settings-about");
  if (about) about.before(card);
  else content.append(card);
};

const observer = new MutationObserver(ensureUpdateCard);
observer.observe(document.body, { childList: true, subtree: true });
ensureUpdateCard();
