(() => {
  if (window.top !== window || document.getElementById("chatgpt-auth-island")) return;

  const permissionWords = /\b(permission|permissions|authorize|authorization|access|allow|approve)\b|权限|授权|允许|批准/i;
  const stopWords = /(?:stop|停止).*(?:generat|stream|生成|输出)/i;
  const actions = new WeakMap();
  let wasBusy = false, initialized = false, completionTimer;

  const island = document.createElement("section");
  island.id = "chatgpt-auth-island";
  island.innerHTML = `
    <div class="island-orb"></div>
    <div class="island-copy"><strong>Auth Island</strong><span>Watching this ChatGPT conversation</span></div>
    <div class="island-detail" aria-live="polite"></div>`;
  document.documentElement.append(island);
  const copy = island.querySelector(".island-copy"), detail = island.querySelector(".island-detail");

  const label = (node) => (node.getAttribute("aria-label") || node.innerText || node.textContent || "").replace(/\s+/g, " ").trim();
  const controls = (root) => [...root.querySelectorAll("button,[role='button']")].filter((node) => !node.disabled && label(node));
  function findRequests() {
    const dialogs = [...document.querySelectorAll("[role='dialog'],[role='alertdialog'],[aria-modal='true']")];
    const inDialogs = dialogs.flatMap((dialog) => {
      if (!permissionWords.test(label(dialog))) return [];
      const context = label(dialog).slice(0, 220);
      return controls(dialog).map((node) => ({ node, name: label(node), context }));
    });
    if (inDialogs.length) return inDialogs;
    return controls(document).flatMap((node) => {
      if (!/^(allow|approve|authorize|permit|允许|批准|授权)/i.test(label(node))) return [];
      const scope = node.closest("[data-state='open'],[role='menu'],[role='group']") || node.parentElement?.parentElement;
      const context = label(scope);
      return permissionWords.test(context) ? [{ node, name: label(node), context: context.slice(0, 220) }] : [];
    });
  }

  function showRequests(requests) {
    if (!requests.length) return false;
    island.className = "expanded";
    copy.innerHTML = `<strong>Approval needed</strong><span>${requests[0].context}</span>`;
    detail.replaceChildren();
    requests.forEach(({ node, name }) => {
      const action = document.createElement("button");
      action.className = "island-action";
      action.textContent = name;
      actions.set(action, node);
      action.onclick = () => {
        const target = actions.get(action);
        if (target?.isConnected) target.click();
      };
      detail.append(action);
    });
    return true;
  }

  function showIdle() {
    island.className = "";
    copy.innerHTML = "<strong>Auth Island</strong><span>Watching this ChatGPT conversation</span>";
    detail.replaceChildren();
  }

  function complete() {
    clearTimeout(completionTimer);
    island.className = "complete";
    copy.innerHTML = "<strong>Response complete</strong><span>Click to return to this conversation</span>";
    detail.replaceChildren();
    island.onclick = () => chrome.runtime.sendMessage({ type: "focus" });
    chrome.runtime.sendMessage({ type: "complete", url: location.href });
    completionTimer = setTimeout(() => { island.onclick = null; showIdle(); }, 8000);
  }

  function scan() {
    const requests = findRequests();
    const busy = controls(document).some((node) => stopWords.test(label(node)));
    if (initialized && wasBusy && !busy && !requests.length) complete();
    else if (!showRequests(requests) && !island.classList.contains("complete")) showIdle();
    wasBusy = busy;
    initialized = true;
  }

  new MutationObserver((records) => {
    if (records.some((record) => !island.contains(record.target))) scan();
  }).observe(document.documentElement, { childList: true, subtree: true, attributes: true, attributeFilter: ["aria-label", "disabled", "role"] });
  scan();
})();
