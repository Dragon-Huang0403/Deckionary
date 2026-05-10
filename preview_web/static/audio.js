// Audio playback for entry pages and the index audio test.
//
// Two-tier source: server returns either a Wikimedia Commons recording
// (real voice) or a pre-generated Piper TTS file (synthetic). The
// X-Audio-Source response header tells us which; we mark synthetic
// playback with a small ✷ on the button.

// Bounded LRU cache so blob URLs don't leak indefinitely.
const BLOB_CACHE_MAX = 50;
const blobCache = new Map();

function rememberBlob(word, entry) {
  if (blobCache.has(word)) {
    URL.revokeObjectURL(blobCache.get(word).url);
    blobCache.delete(word);
  }
  blobCache.set(word, entry);
  while (blobCache.size > BLOB_CACHE_MAX) {
    const oldest = blobCache.keys().next().value;
    URL.revokeObjectURL(blobCache.get(oldest).url);
    blobCache.delete(oldest);
  }
}

async function fetchAudio(word) {
  if (blobCache.has(word)) return blobCache.get(word);
  const res = await fetch("/audio/" + encodeURIComponent(word));
  if (!res.ok) throw new Error("HTTP " + res.status);
  const source = res.headers.get("X-Audio-Source") || "";
  const blob = await res.blob();
  const entry = { url: URL.createObjectURL(blob), source };
  rememberBlob(word, entry);
  return entry;
}

async function play(word, button) {
  if (!word) return;
  button.classList.remove("failed");
  button.classList.add("loading");
  try {
    const { url, source } = await fetchAudio(word);
    button.classList.toggle("synth", source === "piper-tts");
    button.title = source === "piper-tts"
      ? "Pronunciación sintética (Piper TTS)"
      : "Pronunciación humana (Wikimedia Commons)";
    const audio = new Audio(url);
    audio.onended = () => button.classList.remove("loading");
    audio.onerror = () => {
      button.classList.remove("loading");
      button.classList.add("failed");
    };
    await audio.play();
  } catch (e) {
    button.classList.remove("loading");
    button.classList.add("failed");
    button.title = "Sin audio disponible";
  }
}

async function playTest(word, statusEl) {
  if (!word) return;
  statusEl.textContent = "Cargando...";
  try {
    const { url, source } = await fetchAudio(word);
    const tag = source === "piper-tts" ? " (sintética)" : "";
    const audio = new Audio(url);
    audio.onplaying = () => { statusEl.textContent = "Reproduciendo " + word + tag; };
    audio.onended = () => { statusEl.textContent = "Listo" + tag; };
    audio.onerror = () => { statusEl.textContent = "Error al reproducir " + word; };
    await audio.play();
  } catch (e) {
    statusEl.textContent = "Sin audio para “" + word + "”";
  }
}

document.addEventListener("click", (e) => {
  const btn = e.target.closest("[data-audio-word]");
  if (btn) {
    e.preventDefault();
    play(btn.dataset.audioWord, btn);
    return;
  }
  const test = e.target.closest("[data-audio-test]");
  if (test) {
    e.preventDefault();
    const input = document.getElementById("audio-test-word");
    const status = document.getElementById("audio-test-status");
    playTest(input.value.trim(), status);
  }
});
