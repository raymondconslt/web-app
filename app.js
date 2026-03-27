function updateServerTime() {
  const serverTimeEl = document.getElementById("server-time");
  const now = new Date();
  serverTimeEl.textContent = now.toLocaleString();
}

document.getElementById("refresh-btn").addEventListener("click", updateServerTime);

updateServerTime();
