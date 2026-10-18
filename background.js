const completed = new Map();

chrome.runtime.onMessage.addListener((message, sender) => {
  if (message.type === "complete" && sender.tab?.id) {
    const id = `chatgpt-complete-${sender.tab.id}`;
    completed.set(id, { tabId: sender.tab.id, url: message.url });
    chrome.notifications.create(id, {
      type: "basic",
      iconUrl: "icon.svg",
      title: "ChatGPT response complete",
      message: "Click to return to this conversation."
    });
  }
  if (message.type === "focus" && sender.tab?.id) chrome.tabs.update(sender.tab.id, { active: true });
});

chrome.notifications.onClicked.addListener((id) => {
  const item = completed.get(id);
  if (!item) return;
  chrome.tabs.update(item.tabId, { active: true, url: item.url });
  chrome.tabs.get(item.tabId, (tab) => chrome.windows.update(tab.windowId, { focused: true }));
  chrome.notifications.clear(id);
});
