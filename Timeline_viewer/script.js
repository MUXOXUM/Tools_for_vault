const START_YEAR = 2005;
const START_DATE = new Date(`${START_YEAR}-01-01T00:00:00Z`);
const DAY_MS = 24 * 60 * 60 * 1000;
const MONTH_LABEL_MIN_PX_PER_DAY = 0.42;
const DATE_RE = /^\d{4}-\d{2}-\d{2}$/;
const YEAR_RE = /^\d{4}$/;
const YEAR_MONTH_RE = /^(\d{4})-(\d{2})$/;
const ISO_DURATION_RE =
  /^P(?:(\d+)Y)?(?:(\d+)M)?(?:(\d+)W)?(?:(\d+)D)?(?:T(?:(\d+)H)?(?:(\d+)M)?(?:(\d+(?:[.,]\d+)?)S)?)?$/i;
const TIMELINE_PERIODS = [
  { start: "2012-09-01", end: "2016-06-01", label: "Начальная школа" },
  { start: "2016-09-01", end: "2021-06-01", label: "Средняя школа" },
  { start: "2021-09-01", end: "2023-06-01", label: "Старшие классы" },
  { start: "2023-09-01", end: "2027-06-15", label: "Университет" },
];
const BIRTH_MARKER_DATE = "2005-06-04";
const BIRTH_MARKER_LABEL = "Рождение";
const IMAGE_EXT = new Set(["jpg", "jpeg", "png", "webp"]);
const VIDEO_EXT = new Set(["mp4", "webm"]);

const state = {
  sourceType: null,
  rootHandle: null,
  fallbackByFolder: new Map(),
  events: [],
  allTags: [],
  tagColors: new Map(),
  activeTags: new Set(),
  includeUntagged: true,
  filteredEvents: [],
  selectedEventId: null,
  zoom: 0.38,
  minZoom: 0.05,
  maxZoom: 3.2,
  dayWidthBase: 0.45,
  mediaUrls: [],
  mediaRenderToken: 0,
  viewerItems: [],
  viewerIndex: 0,
};

const pickButton = document.getElementById("pick-folder");
const folderInput = document.getElementById("folder-input");
const dropZone = document.getElementById("drop-zone");
const filterBar = document.getElementById("filter-bar");
const app = document.querySelector(".app");
const timelineShell = document.querySelector(".timeline-shell");
const timelineScroll = document.getElementById("timeline-scroll");
const timeline = document.getElementById("timeline");
const panelSplitter = document.getElementById("panel-splitter");
const mediaTitle = document.getElementById("media-title");
const mediaGrid = document.getElementById("media-grid");
const mediaPanel = document.getElementById("media-panel");
const viewer = document.getElementById("viewer");
const viewerClose = document.getElementById("viewer-close");
const viewerPrev = document.getElementById("viewer-prev");
const viewerNext = document.getElementById("viewer-next");
const viewerStage = document.getElementById("viewer-stage");
const BASE_PAGE_TITLE = document.title;
let mediaLazyObserver = null;
const panelResizeState = {
  active: false,
  pointerId: null,
  startY: 0,
  startTimelineHeight: 0,
  totalFlexibleHeight: 0,
};
const MIN_TIMELINE_HEIGHT = 180;
const MIN_MEDIA_HEIGHT = 180;

pickButton.addEventListener("click", chooseFolder);
folderInput.addEventListener("change", () => {
  loadFromFileList(Array.from(folderInput.files || []));
});

dropZone.addEventListener("dragover", (event) => {
  event.preventDefault();
  dropZone.classList.add("active");
});

dropZone.addEventListener("dragleave", () => {
  dropZone.classList.remove("active");
});

dropZone.addEventListener("drop", async (event) => {
  event.preventDefault();
  dropZone.classList.remove("active");

  try {
    const items = Array.from(event.dataTransfer?.items || []);
    if (items.length && "getAsFileSystemHandle" in items[0]) {
      for (const item of items) {
        if (item.kind !== "file") continue;
        const handle = await item.getAsFileSystemHandle();
        if (handle && handle.kind === "directory") {
          await loadFromHandle(handle);
          return;
        }
      }
    }
  } catch (_) {}

  const files = Array.from(event.dataTransfer?.files || []);
  if (files.length) {
    loadFromFileList(files);
  }
});

timelineScroll.addEventListener(
  "wheel",
  (event) => {
    if (!state.filteredEvents.length) return;

    event.preventDefault();
    if (event.ctrlKey) {
      const prevScale = state.dayWidthBase * state.zoom;
      const rect = timelineScroll.getBoundingClientRect();
      const cursorX = event.clientX - rect.left;
      const scrollLeft = timelineScroll.scrollLeft;
      const dayAtCursor = (scrollLeft + cursorX) / prevScale;

      const zoomStep = event.deltaY < 0 ? 1.12 : 1 / 1.12;
      state.zoom = clamp(state.zoom * zoomStep, state.minZoom, state.maxZoom);

      renderTimeline();

      const nextScale = state.dayWidthBase * state.zoom;
      const nextScroll = dayAtCursor * nextScale - cursorX;
      timelineScroll.scrollLeft = Math.max(0, nextScroll);
      return;
    }

    let delta = Math.abs(event.deltaX) > Math.abs(event.deltaY) ? event.deltaX : event.deltaY;
    if (event.deltaMode === WheelEvent.DOM_DELTA_LINE) delta *= 16;
    if (event.deltaMode === WheelEvent.DOM_DELTA_PAGE) delta *= timelineScroll.clientWidth;
    timelineScroll.scrollLeft += delta;
  },
  { passive: false }
);

viewerClose.addEventListener("click", closeViewer);
viewerPrev.addEventListener("click", () => shiftViewer(-1));
viewerNext.addEventListener("click", () => shiftViewer(1));
viewer.addEventListener("click", (event) => {
  if (event.target === viewer) closeViewer();
});

document.addEventListener("keydown", (event) => {
  if (viewer.classList.contains("hidden")) return;
  if (event.key === "Escape") closeViewer();
  if (event.key === "ArrowRight") shiftViewer(1);
  if (event.key === "ArrowLeft") shiftViewer(-1);
});
setupPanelResize();

function clamp(value, min, max) {
  return Math.min(max, Math.max(min, value));
}

function setupPanelResize() {
  if (!panelSplitter || !timelineShell || !mediaPanel) return;

  panelSplitter.addEventListener("pointerdown", (event) => {
    if (event.button !== 0 || !app.classList.contains("loaded")) return;

    const timelineRect = timelineShell.getBoundingClientRect();
    const mediaRect = mediaPanel.getBoundingClientRect();
    panelResizeState.active = true;
    panelResizeState.pointerId = event.pointerId;
    panelResizeState.startY = event.clientY;
    panelResizeState.startTimelineHeight = timelineRect.height;
    panelResizeState.totalFlexibleHeight = timelineRect.height + mediaRect.height;

    panelSplitter.classList.add("active");
    document.body.classList.add("resizing-panels");
    panelSplitter.setPointerCapture(event.pointerId);
    event.preventDefault();
  });

  panelSplitter.addEventListener("pointermove", (event) => {
    if (!panelResizeState.active || event.pointerId !== panelResizeState.pointerId) return;

    const deltaY = event.clientY - panelResizeState.startY;
    const minTimeline = MIN_TIMELINE_HEIGHT;
    const maxTimeline = Math.max(minTimeline, panelResizeState.totalFlexibleHeight - MIN_MEDIA_HEIGHT);
    const nextTimeline = clamp(panelResizeState.startTimelineHeight + deltaY, minTimeline, maxTimeline);

    app.style.setProperty("--timeline-size", `${Math.round(nextTimeline)}px`);
  });

  const stopResize = (event) => {
    if (!panelResizeState.active) return;
    if (event && panelResizeState.pointerId !== null && event.pointerId !== panelResizeState.pointerId) return;

    try {
      if (panelResizeState.pointerId !== null) {
        panelSplitter.releasePointerCapture(panelResizeState.pointerId);
      }
    } catch (_) {}

    panelResizeState.active = false;
    panelResizeState.pointerId = null;
    panelSplitter.classList.remove("active");
    document.body.classList.remove("resizing-panels");
  };

  panelSplitter.addEventListener("pointerup", stopResize);
  panelSplitter.addEventListener("pointercancel", stopResize);
}

function parseFolderNameAnalysis(name) {
  const matches = Array.from(name.matchAll(/\[([^\]]+)\]/g));
  if (!matches.length) {
    return { parsed: null, reason: "Нет блоков в квадратных скобках" };
  }

  let dateBlockIndex = -1;
  let parsedDate = null;
  for (let i = 0; i < matches.length; i += 1) {
    const raw = matches[i][1].trim();
    const parsed = parseDateBlock(raw);
    if (parsed) {
      dateBlockIndex = i;
      parsedDate = parsed;
      break;
    }
  }
  if (dateBlockIndex < 0 || !parsedDate) {
    return { parsed: null, reason: "Нет валидного блока даты" };
  }

  const tags = matches
    .filter((_, idx) => idx !== dateBlockIndex)
    .map((m) => m[1].trim().toLowerCase())
    .filter(Boolean);

  const dateMatch = matches[dateBlockIndex];
  const nameWithoutDate =
    name.slice(0, dateMatch.index) + name.slice(dateMatch.index + dateMatch[0].length);
  const title = nameWithoutDate.replace(/\[[^\]]+\]/g, " ").replace(/\s+/g, " ").trim();
  if (!title) {
    return { parsed: null, reason: "Пустой заголовок после удаления блоков [...]" };
  }

  return {
    parsed: {
      startISO: parsedDate.startISO,
      endISO: parsedDate.endISO,
      startDate: parsedDate.startDate,
      endDate: parsedDate.endDate,
      tags: [...new Set(tags)],
      title,
    },
    reason: null,
  };
}

function parseFolderName(name) {
  return parseFolderNameAnalysis(name).parsed;
}

function parseDateBlock(rawBlock) {
  const normalized = rawBlock.replace(/\u2044/g, "/").trim();
  if (!normalized) return null;

  const parts = normalized.split(/\s*\/\s*/).filter(Boolean);
  if (parts.length > 2 || parts.length === 0) return null;

  const startToken = parseDateToken(parts[0]);
  if (!startToken) return null;
  const startISO = startToken.startISO;
  const startDate = startToken.startDate;

  if (parts.length === 1) {
    return {
      startISO: startToken.startISO,
      endISO: startToken.endISO,
      startDate: startToken.startDate,
      endDate: startToken.endDate,
    };
  }

  const rhs = parts[1];
  const endToken = parseDateToken(rhs);
  if (endToken) {
    if (endToken.endDate < startDate) return null;
    return {
      startISO,
      endISO: endToken.endISO,
      startDate,
      endDate: endToken.endDate,
    };
  }

  const endDate = endDateFromDuration(startDate, rhs);
  if (!endDate) return null;
  return {
    startISO,
    endISO: toISODate(endDate),
    startDate,
    endDate,
  };
}

function parseDateToken(rawToken) {
  const token = rawToken.trim();
  if (!token) return null;

  if (DATE_RE.test(token)) {
    const date = parseISODate(token);
    if (!date) return null;
    return {
      startISO: token,
      endISO: token,
      startDate: date,
      endDate: new Date(date.getTime()),
    };
  }

  if (YEAR_RE.test(token)) {
    const startISO = `${token}-01-01`;
    const startDate = parseISODate(startISO);
    if (!startDate) return null;
    return {
      startISO,
      endISO: startISO,
      startDate,
      endDate: new Date(startDate.getTime()),
    };
  }

  const monthMatch = token.match(YEAR_MONTH_RE);
  if (monthMatch) {
    const month = Number(monthMatch[2]);
    if (month < 1 || month > 12) return null;
    const startISO = `${monthMatch[1]}-${monthMatch[2]}-01`;
    const startDate = parseISODate(startISO);
    if (!startDate) return null;
    return {
      startISO,
      endISO: startISO,
      startDate,
      endDate: new Date(startDate.getTime()),
    };
  }

  return null;
}

function parseISODate(isoDate) {
  if (!DATE_RE.test(isoDate)) return null;
  const parsed = new Date(`${isoDate}T00:00:00Z`);
  if (Number.isNaN(parsed.valueOf())) return null;
  return parsed;
}

function toISODate(date) {
  return date.toISOString().slice(0, 10);
}

function endDateFromDuration(startDate, durationRaw) {
  const duration = durationRaw.trim().toUpperCase();
  const match = duration.match(ISO_DURATION_RE);
  if (!match) return null;

  const hasComponent = match.slice(1).some((part) => part && part !== "0" && part !== "0.0");
  if (!hasComponent) return null;

  const years = Number(match[1] || 0);
  const months = Number(match[2] || 0);
  const weeks = Number(match[3] || 0);
  const days = Number(match[4] || 0);
  const hours = Number(match[5] || 0);
  const minutes = Number(match[6] || 0);
  const seconds = Number((match[7] || "0").replace(",", "."));
  if (
    [years, months, weeks, days, hours, minutes, seconds].some((n) => !Number.isFinite(n) || n < 0)
  ) {
    return null;
  }

  const endExclusive = new Date(startDate.getTime());
  if (years) endExclusive.setUTCFullYear(endExclusive.getUTCFullYear() + years);
  if (months) endExclusive.setUTCMonth(endExclusive.getUTCMonth() + months);
  if (weeks) endExclusive.setUTCDate(endExclusive.getUTCDate() + weeks * 7);
  if (days) endExclusive.setUTCDate(endExclusive.getUTCDate() + days);
  if (hours) endExclusive.setUTCHours(endExclusive.getUTCHours() + hours);
  if (minutes) endExclusive.setUTCMinutes(endExclusive.getUTCMinutes() + minutes);
  if (seconds) endExclusive.setTime(endExclusive.getTime() + Math.round(seconds * 1000));

  if (!(endExclusive > startDate)) return null;
  const inclusiveMoment = new Date(endExclusive.getTime() - 1);
  return new Date(
    Date.UTC(
      inclusiveMoment.getUTCFullYear(),
      inclusiveMoment.getUTCMonth(),
      inclusiveMoment.getUTCDate()
    )
  );
}

function daysFromStart(date) {
  return Math.floor((date.getTime() - START_DATE.getTime()) / DAY_MS);
}

function collectTags(events) {
  const set = new Set();
  for (const event of events) {
    for (const tag of event.tags) set.add(tag);
  }
  return Array.from(set).sort((a, b) => a.localeCompare(b));
}

function colorForTag(index) {
  const hue = (index * 137.508) % 360;
  return {
    strong: `hsl(${hue} 65% 64%)`,
    soft: `hsl(${hue} 30% 25%)`,
    border: `hsl(${hue} 38% 48%)`,
    text: `hsl(${hue} 70% 86%)`,
    eventTop: `hsl(${hue} 46% 55%)`,
    eventBottom: `hsl(${hue} 42% 44%)`,
    eventBorder: `hsl(${hue} 40% 58%)`,
  };
}

function buildTagColors(tags) {
  const map = new Map();
  tags.forEach((tag, i) => {
    map.set(tag, colorForTag(i));
  });
  return map;
}

function folderWord(count) {
  const abs = Math.abs(count) % 100;
  const last = abs % 10;
  if (abs > 10 && abs < 20) return "папок";
  if (last === 1) return "папка";
  if (last >= 2 && last <= 4) return "папки";
  return "папок";
}

function updatePageTitle(folderCount) {
  if (!folderCount) {
    document.title = BASE_PAGE_TITLE;
    return;
  }
  document.title = `${BASE_PAGE_TITLE} (${folderCount} ${folderWord(folderCount)})`;
}

function logSkippedFolders(totalFolders, skipped) {
  if (!skipped.length) return;
  const loaded = totalFolders - skipped.length;
  console.groupCollapsed(
    `[Timeline] Загружено ${loaded} из ${totalFolders}. Пропущено: ${skipped.length}`
  );
  for (const item of skipped) {
    console.warn(`${item.name} -> ${item.reason}`);
  }
  console.groupEnd();
}

async function chooseFolder() {
  if (window.showDirectoryPicker) {
    try {
      const handle = await window.showDirectoryPicker({ mode: "read" });
      await loadFromHandle(handle);
      return;
    } catch (_) {}
  }
  folderInput.click();
}

async function loadFromHandle(rootHandle) {
  resetState();
  setPickerHidden(true);
  state.sourceType = "handle";
  state.rootHandle = rootHandle;

  const entries = [];
  for await (const entry of rootHandle.values()) {
    if (entry.kind !== "directory") continue;
    entries.push(entry);
  }

  const events = [];
  const skipped = [];
  for (const folder of entries) {
    const analysis = parseFolderNameAnalysis(folder.name);
    const parsed = analysis.parsed;
    if (!parsed) {
      skipped.push({ name: folder.name, reason: analysis.reason || "Неизвестная ошибка парсинга" });
      continue;
    }

    const startDay = daysFromStart(parsed.startDate);
    const endDay = daysFromStart(parsed.endDate);

    events.push({
      id: `${folder.name}__${parsed.startISO}`,
      folderName: folder.name,
      folderHandle: folder,
      ...parsed,
      startDay,
      endDay,
    });
  }

  logSkippedFolders(entries.length, skipped);
  applyLoadedEvents(events);
}

function loadFromFileList(files) {
  resetState();
  setPickerHidden(true);
  state.sourceType = "filelist";

  const byFolder = new Map();
  for (const file of files) {
    const rel = file.webkitRelativePath || file.name;
    const parts = rel.split("/").filter(Boolean);
    if (parts.length < 2) continue;
    const firstFolder = parts[0];
    if (!byFolder.has(firstFolder)) byFolder.set(firstFolder, []);
    byFolder.get(firstFolder).push(file);
  }

  state.fallbackByFolder = byFolder;

  const events = [];
  const skipped = [];
  for (const [folderName] of byFolder.entries()) {
    const analysis = parseFolderNameAnalysis(folderName);
    const parsed = analysis.parsed;
    if (!parsed) {
      skipped.push({ name: folderName, reason: analysis.reason || "Неизвестная ошибка парсинга" });
      continue;
    }

    const startDay = daysFromStart(parsed.startDate);
    const endDay = daysFromStart(parsed.endDate);

    events.push({
      id: `${folderName}__${parsed.startISO}`,
      folderName,
      folderHandle: null,
      ...parsed,
      startDay,
      endDay,
    });
  }

  logSkippedFolders(byFolder.size, skipped);
  applyLoadedEvents(events);
}

function applyLoadedEvents(events) {
  events.sort((a, b) => a.startDay - b.startDay || a.endDay - b.endDay || a.title.localeCompare(b.title));
  state.events = events;
  state.allTags = collectTags(events);
  state.tagColors = buildTagColors(state.allTags);
  state.activeTags = new Set(state.allTags);
  updatePageTitle(events.length);

  renderFilters();
  applyFilters();
}

function resetState() {
  state.mediaRenderToken += 1;
  clearMediaUrls();
  disconnectMediaObserver();
  state.rootHandle = null;
  state.fallbackByFolder = new Map();
  state.events = [];
  state.allTags = [];
  state.tagColors = new Map();
  state.activeTags = new Set();
  state.includeUntagged = true;
  state.filteredEvents = [];
  state.selectedEventId = null;
  state.viewerItems = [];
  setMediaTitle("");
  closeViewer();
  updatePageTitle(0);
}

function setPickerHidden(hidden) {
  app.classList.toggle("loaded", hidden);
}

function applyFilters() {
  state.filteredEvents = state.events.filter((event) => {
    if (!event.tags.length) return state.includeUntagged;
    for (const tag of event.tags) {
      if (state.activeTags.has(tag)) return true;
    }
    return false;
  });

  if (!state.filteredEvents.some((e) => e.id === state.selectedEventId)) {
    state.selectedEventId = null;
    setMediaTitle("");
    renderMedia([]);
  }

  renderTimeline();
}

function renderFilters() {
  filterBar.innerHTML = "";

  const untaggedBtn = document.createElement("button");
  untaggedBtn.type = "button";
  untaggedBtn.className = "tag-btn active";
  untaggedBtn.textContent = "без тегов";
  untaggedBtn.style.setProperty("--tag-color", "#a3b0c2");
  untaggedBtn.style.setProperty("--tag-soft", "#313947");
  untaggedBtn.style.setProperty("--tag-text", "#dae4f3");
  untaggedBtn.style.setProperty("--tag-border", "#5a687d");
  untaggedBtn.addEventListener("click", () => {
    state.includeUntagged = !state.includeUntagged;
    untaggedBtn.classList.toggle("active", state.includeUntagged);
    applyFilters();
  });
  filterBar.appendChild(untaggedBtn);

  for (const tag of state.allTags) {
    const btn = document.createElement("button");
    btn.type = "button";
    btn.className = "tag-btn active";
    btn.textContent = tag;
    btn.dataset.tag = tag;
    const tagColor = state.tagColors.get(tag);
    if (tagColor) {
      btn.style.setProperty("--tag-color", tagColor.strong);
      btn.style.setProperty("--tag-soft", tagColor.soft);
      btn.style.setProperty("--tag-text", tagColor.text);
      btn.style.setProperty("--tag-border", tagColor.border);
    }
    btn.addEventListener("click", () => {
      if (state.activeTags.has(tag)) {
        state.activeTags.delete(tag);
        btn.classList.remove("active");
      } else {
        state.activeTags.add(tag);
        btn.classList.add("active");
      }
      applyFilters();
    });
    filterBar.appendChild(btn);
  }
}

function assignLanes(events, pxPerDay) {
  const laneRightPx = [];

  for (const event of events) {
    const isPoint = event.startDay === event.endDay;
    const left = event.startDay * pxPerDay;
    const spanDays = Math.max(1, event.endDay - event.startDay + 1);
    const width = Math.max(isPoint ? 10 : 12, spanDays * pxPerDay);
    const right = left + width;

    let lane = -1;
    for (let i = 0; i < laneRightPx.length; i += 1) {
      if (left > laneRightPx[i] + 2) {
        lane = i;
        laneRightPx[i] = right;
        break;
      }
    }
    if (lane === -1) {
      lane = laneRightPx.length;
      laneRightPx.push(right);
    }

    event.lane = lane;
    event.leftPx = left;
    event.widthPx = width;
  }

  return laneRightPx.length;
}

function monthStartDays(from, to) {
  const out = [];
  const d = new Date(Date.UTC(from.getUTCFullYear(), from.getUTCMonth(), 1));

  while (d <= to) {
    out.push(new Date(d));
    d.setUTCMonth(d.getUTCMonth() + 1);
  }
  return out;
}

function renderTimeline() {
  timeline.innerHTML = "";

  if (!state.filteredEvents.length) {
    timeline.style.width = "100%";
    timeline.style.height = "100%";
    return;
  }

  const pxPerDay = state.dayWidthBase * state.zoom;
  const maxEnd = state.filteredEvents.reduce((m, e) => Math.max(m, e.endDay), 0);
  const totalDays = Math.max(1, maxEnd + 366);
  const width = Math.max(timelineScroll.clientWidth, totalDays * pxPerDay);
  const fromDate = START_DATE;
  const toDate = new Date(START_DATE.getTime() + totalDays * DAY_MS);

  timeline.style.width = `${width}px`;

  const yearRow = document.createElement("div");
  yearRow.className = "year-row";
  timeline.appendChild(yearRow);

  const monthRow = document.createElement("div");
  monthRow.className = "month-row";
  timeline.appendChild(monthRow);

  const eventsLayer = document.createElement("div");
  eventsLayer.className = "events-layer";
  timeline.appendChild(eventsLayer);

  const periodsLayer = document.createElement("div");
  periodsLayer.className = "period-bands";
  timeline.appendChild(periodsLayer);

  const laneCount = assignLanes(state.filteredEvents, pxPerDay);
  const laneHeight = 22;
  const eventsHeight = Math.max(180, laneCount * laneHeight + 30);
  eventsLayer.style.height = eventsHeight + "px";
  timeline.style.height = eventsHeight + 72 + "px";

  for (let y = START_YEAR; y <= toDate.getUTCFullYear(); y += 1) {
    const yearDate = new Date(Date.UTC(y, 0, 1));
    const day = daysFromStart(yearDate);
    const x = day * pxPerDay;

    const line = document.createElement("div");
    line.className = "grid-line";
    line.style.left = `${x}px`;
    timeline.appendChild(line);

    const label = document.createElement("div");
    label.className = "tick-label";
    label.style.left = `${x}px`;
    label.textContent = String(y);
    yearRow.appendChild(label);
  }

  const showMonths = pxPerDay > MONTH_LABEL_MIN_PX_PER_DAY;
  if (showMonths) {
    for (const m of monthStartDays(fromDate, toDate)) {
      const day = daysFromStart(m);
      const x = day * pxPerDay;
      const label = document.createElement("div");
      label.className = "month-label";
      label.style.left = `${x}px`;
      const mm = String(m.getUTCMonth() + 1).padStart(2, "0");
      label.textContent = mm;
      monthRow.appendChild(label);
    }
  }

  renderBirthMarker(pxPerDay, width);
  renderTimelinePeriods(periodsLayer, pxPerDay, width);

  for (const event of state.filteredEvents) {
    const el = document.createElement("button");
    const isPoint = event.startDay === event.endDay;
    const eventTag = event.tags[0];
    const tagColor = eventTag ? state.tagColors.get(eventTag) : null;

    el.type = "button";
    el.className = `event ${isPoint ? "point" : "range"}`;
    if (event.id === state.selectedEventId) el.classList.add("active");

    el.style.left = `${event.leftPx}px`;
    el.style.top = `${event.lane * laneHeight}px`;
    el.style.width = `${event.widthPx}px`;
    if (tagColor) {
      el.style.setProperty("--event-top", tagColor.eventTop);
      el.style.setProperty("--event-bottom", tagColor.eventBottom);
      el.style.setProperty("--event-border", tagColor.eventBorder);
    }

    const ariaDate = event.startISO === event.endISO ? event.startISO : `${event.startISO}/${event.endISO}`;
    el.setAttribute("aria-label", `${ariaDate} ${event.title}`);

    el.addEventListener("click", () => onSelectEvent(event.id));
    eventsLayer.appendChild(el);
  }
}

function renderBirthMarker(pxPerDay, timelineWidth) {
  const birthDate = parseISODate(BIRTH_MARKER_DATE);
  if (!birthDate) return;

  const x = daysFromStart(birthDate) * pxPerDay;
  if (x < 0 || x > timelineWidth) return;

  const line = document.createElement("div");
  line.className = "birth-line";
  line.style.left = `${x}px`;
  line.setAttribute("aria-label", `${BIRTH_MARKER_DATE} ${BIRTH_MARKER_LABEL}`);
  timeline.appendChild(line);

  const label = document.createElement("div");
  label.className = "birth-label";
  label.style.left = `${x}px`;
  label.textContent = BIRTH_MARKER_LABEL;
  timeline.appendChild(label);
}

function renderTimelinePeriods(layer, pxPerDay, timelineWidth) {
  for (const period of TIMELINE_PERIODS) {
    const startDate = parseISODate(period.start);
    const endDate = parseISODate(period.end);
    if (!startDate || !endDate || endDate < startDate) continue;

    const startDay = daysFromStart(startDate);
    const endDay = daysFromStart(endDate);
    const left = startDay * pxPerDay;
    const bandWidth = Math.max(1, (endDay - startDay + 1) * pxPerDay);
    if (left >= timelineWidth || left + bandWidth <= 0) continue;

    const clampedLeft = Math.max(0, left);
    const clampedWidth = Math.min(bandWidth - Math.max(0, -left), timelineWidth - clampedLeft);
    if (clampedWidth <= 0) continue;

    const band = document.createElement("div");
    band.className = "timeline-period";
    band.style.left = clampedLeft + "px";
    band.style.width = clampedWidth + "px";
    band.setAttribute("aria-label", period.start + " - " + period.end + ": " + period.label);

    const text = document.createElement("span");
    text.className = "period-label";
    text.textContent = period.label;
    band.appendChild(text);

    layer.appendChild(band);
  }
}

async function onSelectEvent(eventId) {
  state.selectedEventId = eventId;
  renderTimeline();

  const event = state.filteredEvents.find((e) => e.id === eventId);
  if (!event) {
    setMediaTitle("");
    renderMedia([]);
    return;
  }

  setMediaTitle(event.folderName);

  if (state.sourceType === "handle") {
    const files = await readEventFilesFromHandle(event.folderHandle);
    renderMedia(files);
    return;
  }

  const files = state.fallbackByFolder.get(event.folderName) || [];
  renderMedia(files);
}

async function readEventFilesFromHandle(folderHandle) {
  const files = [];
  if (!folderHandle) return files;

  for await (const item of folderHandle.values()) {
    if (item.kind !== "file") continue;
    const f = await item.getFile();
    files.push(f);
  }

  return files;
}

function mediaType(fileName) {
  const ext = fileName.split(".").pop()?.toLowerCase() || "";
  if (IMAGE_EXT.has(ext)) return "image";
  if (VIDEO_EXT.has(ext)) return "video";
  return null;
}

function clearMediaUrls() {
  for (const u of state.mediaUrls) URL.revokeObjectURL(u);
  state.mediaUrls = [];
}

function disconnectMediaObserver() {
  if (!mediaLazyObserver) return;
  mediaLazyObserver.disconnect();
  mediaLazyObserver = null;
}

function ensureMediaObserver() {
  if (mediaLazyObserver) return mediaLazyObserver;
  mediaLazyObserver = new IntersectionObserver(
    (entries, observer) => {
      for (const entry of entries) {
        if (!entry.isIntersecting) continue;
        const node = entry.target;
        const src = node.dataset.src;
        if (!src) {
          observer.unobserve(node);
          continue;
        }
        node.src = src;
        delete node.dataset.src;
        if (node.tagName === "VIDEO") node.load();
        observer.unobserve(node);
      }
    },
    {
      root: mediaGrid,
      rootMargin: "320px 0px",
      threshold: 0.01,
    }
  );
  return mediaLazyObserver;
}

function setMediaTitle(value) {
  mediaTitle.textContent = value;
}

function renderMedia(files) {
  const renderToken = ++state.mediaRenderToken;
  clearMediaUrls();
  disconnectMediaObserver();
  mediaGrid.innerHTML = "";
  state.viewerItems = [];
  state.viewerIndex = 0;

  const mediaFiles = files.filter((f) => mediaType(f.name));
  if (!mediaFiles.length) {
    return;
  }

  mediaFiles.sort((a, b) => a.name.localeCompare(b.name));

  const observer = ensureMediaObserver();
  const chunkSize = 60;
  let index = 0;

  const renderChunk = () => {
    if (renderToken !== state.mediaRenderToken) return;
    const fragment = document.createDocumentFragment();
    const end = Math.min(index + chunkSize, mediaFiles.length);

    for (; index < end; index += 1) {
      const currentIndex = index;
      const file = mediaFiles[index];
      const type = mediaType(file.name);
      const url = URL.createObjectURL(file);
      state.mediaUrls.push(url);
      state.viewerItems.push({ type, url });

      let node;
      if (type === "image") {
        node = document.createElement("img");
        node.loading = "lazy";
        node.decoding = "async";
        node.fetchPriority = "low";
        node.className = "media-thumb";
        node.alt = file.name;
      } else {
        node = document.createElement("video");
        node.className = "media-thumb video";
        node.preload = "none";
        node.muted = true;
        node.playsInline = true;
      }

      node.dataset.src = url;
      node.addEventListener("click", () => openViewer(currentIndex));
      observer.observe(node);
      fragment.appendChild(node);
    }

    mediaGrid.appendChild(fragment);

    if (index < mediaFiles.length) {
      requestAnimationFrame(renderChunk);
    }
  };

  requestAnimationFrame(renderChunk);
}

function openViewer(index) {
  if (!state.viewerItems.length) return;
  state.viewerIndex = clamp(index, 0, state.viewerItems.length - 1);
  viewer.classList.remove("hidden");
  renderViewerSlide();
}

function closeViewer() {
  viewer.classList.add("hidden");
  viewerStage.innerHTML = "";
}

function shiftViewer(step) {
  if (!state.viewerItems.length) return;
  const next = (state.viewerIndex + step + state.viewerItems.length) % state.viewerItems.length;
  state.viewerIndex = next;
  renderViewerSlide();
}

function renderViewerSlide() {
  viewerStage.innerHTML = "";
  const item = state.viewerItems[state.viewerIndex];
  if (!item) return;

  if (item.type === "image") {
    const img = document.createElement("img");
    img.className = "viewer-media";
    img.src = item.url;
    img.alt = "";
    viewerStage.appendChild(img);
    return;
  }

  const video = document.createElement("video");
  video.className = "viewer-media";
  video.src = item.url;
  video.controls = true;
  video.autoplay = true;
  viewerStage.appendChild(video);
}
