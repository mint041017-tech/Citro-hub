(function () {
  "use strict";

  var demo = window.CITRO_DEMO;
  if (!demo) return;

  var numberFormat = new Intl.NumberFormat("zh-CN");
  var decimalFormat = new Intl.NumberFormat("zh-CN", {
    minimumFractionDigits: 1,
    maximumFractionDigits: 1
  });

  var state = {
    rangeId: demo.defaultRange,
    query: "",
    tasks: demo.tasks.map(function (task) {
      return Object.assign({}, task);
    }),
    notifications: demo.notifications.map(function (notification) {
      return Object.assign({}, notification);
    })
  };

  var elements = {
    sidebar: document.getElementById("sidebar"),
    workspaceColumn: document.querySelector(".workspace-column"),
    menuButton: document.getElementById("menu-button"),
    drawerClose: document.getElementById("drawer-close"),
    navScrim: document.getElementById("nav-scrim"),
    navLinks: Array.prototype.slice.call(document.querySelectorAll(".nav-link[data-section]")),
    searchForm: document.getElementById("search-form"),
    searchInput: document.getElementById("search-input"),
    searchClear: document.getElementById("search-clear"),
    filterStrip: document.getElementById("filter-strip"),
    filterQuery: document.getElementById("filter-query"),
    filterTaskCount: document.getElementById("filter-task-count"),
    filterNotificationCount: document.getElementById("filter-notification-count"),
    filterClear: document.getElementById("filter-clear"),
    rangeButtons: document.getElementById("range-buttons"),
    rangePeriod: document.getElementById("range-period"),
    rangeGranularity: document.getElementById("range-granularity"),
    metricsGrid: document.getElementById("metrics-grid"),
    exportButton: document.getElementById("export-button"),
    revenueSubtitle: document.getElementById("revenue-subtitle"),
    revenueTotal: document.getElementById("revenue-total"),
    revenueChange: document.getElementById("revenue-change"),
    revenueChartWrap: document.getElementById("revenue-chart-wrap"),
    revenueChartShell: document.getElementById("revenue-chart-shell"),
    chartTooltip: document.getElementById("chart-tooltip"),
    chartPointsNote: document.getElementById("chart-points-note"),
    revenueChartSummary: document.getElementById("revenue-chart-summary"),
    revenueTableCaption: document.getElementById("revenue-table-caption"),
    revenueTableBody: document.getElementById("revenue-table-body"),
    planDonut: document.getElementById("plan-donut"),
    planTotal: document.getElementById("plan-total"),
    planList: document.getElementById("plan-list"),
    taskCount: document.getElementById("task-count"),
    taskPercent: document.getElementById("task-percent"),
    taskProgress: document.getElementById("task-progress"),
    taskProgressTrack: document.getElementById("task-progress-track"),
    taskList: document.getElementById("task-list"),
    taskEmpty: document.getElementById("task-empty"),
    taskEmptyClear: document.getElementById("task-empty-clear"),
    navTaskBadge: document.getElementById("nav-task-badge"),
    teamList: document.getElementById("team-list"),
    teamCount: document.getElementById("team-count"),
    unreadCount: document.getElementById("unread-count"),
    markAllRead: document.getElementById("mark-all-read"),
    notificationList: document.getElementById("notification-list"),
    notificationEmpty: document.getElementById("notification-empty"),
    notificationEmptyClear: document.getElementById("notification-empty-clear"),
    navUnreadBadge: document.getElementById("nav-unread-badge"),
    appFooter: document.querySelector(".app-footer"),
    dataDialog: document.getElementById("data-dialog"),
    dialogClose: document.getElementById("dialog-close"),
    dialogDone: document.getElementById("dialog-done"),
    toast: document.getElementById("toast"),
    liveRegion: document.getElementById("live-region")
  };

  var searchTimer = 0;
  var toastTimer = 0;
  var chartResizeFrame = 0;
  var lastChartWidth = 0;
  var drawerOpen = false;
  var mobileQuery = window.matchMedia("(max-width: 980px)");

  function currentRange() {
    return (
      demo.ranges.find(function (range) {
        return range.id === state.rangeId;
      }) || demo.ranges[0]
    );
  }

  function announce(message) {
    if (!elements.liveRegion) return;
    elements.liveRegion.textContent = "";
    window.setTimeout(function () {
      elements.liveRegion.textContent = message;
    }, 30);
  }

  function showToast(message) {
    if (!elements.toast) return;
    window.clearTimeout(toastTimer);
    elements.toast.textContent = message;
    elements.toast.hidden = false;
    toastTimer = window.setTimeout(function () {
      elements.toast.hidden = true;
    }, 3400);
  }

  function formatCurrency(value) {
    return "¥" + numberFormat.format(value);
  }

  function formatMetricValue(metric) {
    if (metric.kind === "currency") return formatCurrency(metric.value);
    if (metric.kind === "percent") return decimalFormat.format(metric.value) + "%";
    return numberFormat.format(metric.value);
  }

  function formatCompactCurrency(value) {
    if (value >= 1000000) {
      return "¥" + trimDecimal(value / 1000000) + "m";
    }
    if (value >= 1000) {
      return "¥" + trimDecimal(value / 1000) + "k";
    }
    return "¥" + numberFormat.format(value);
  }

  function trimDecimal(value) {
    var rounded = Math.round(value * 10) / 10;
    return Number.isInteger(rounded) ? String(rounded) : rounded.toFixed(1);
  }

  function describeChange(change, unit) {
    var absolute = Math.abs(change);
    var unitText = unit === "pt" ? "pt" : "%";
    var spokenUnit = unit === "pt" ? " 个百分点" : "%";
    var sign = change > 0 ? "+" : change < 0 ? "−" : "±";
    var arrow = change > 0 ? "↑" : change < 0 ? "↓" : "→";
    var direction = change > 0 ? "上升" : change < 0 ? "下降" : "持平";
    return {
      display: sign + decimalFormat.format(absolute) + unitText,
      arrow: arrow,
      direction: direction,
      spoken: direction + " " + decimalFormat.format(absolute) + spokenUnit
    };
  }

  function toneForMetric(metric) {
    if (metric.change === 0) return "neutral";
    var improving = metric.goodWhen === "down" ? metric.change < 0 : metric.change > 0;
    return improving ? "good" : "bad";
  }

  function sparklineMarkup(values) {
    var width = 64;
    var height = 28;
    var padding = 2;
    var minimum = Math.min.apply(null, values);
    var maximum = Math.max.apply(null, values);
    var range = maximum - minimum || 1;
    var points = values.map(function (value, index) {
      var x = padding + (index / Math.max(1, values.length - 1)) * (width - padding * 2);
      var y = height - padding - ((value - minimum) / range) * (height - padding * 2);
      return [x, y];
    });
    var line = points
      .map(function (point, index) {
        return (index === 0 ? "M" : "L") + point[0].toFixed(2) + " " + point[1].toFixed(2);
      })
      .join(" ");
    var first = points[0];
    var last = points[points.length - 1];
    var area =
      "M" +
      first[0].toFixed(2) +
      " " +
      (height - padding) +
      " L" +
      points
        .map(function (point) {
          return point[0].toFixed(2) + " " + point[1].toFixed(2);
        })
        .join(" L") +
      " L" +
      last[0].toFixed(2) +
      " " +
      (height - padding) +
      " Z";

    return (
      '<svg class="metric-spark" viewBox="0 0 64 28" aria-hidden="true" focusable="false">' +
      '<path class="spark-area" d="' +
      area +
      '"></path>' +
      '<path class="spark-line" d="' +
      line +
      '"></path>' +
      "</svg>"
    );
  }

  function renderMetrics(range) {
    elements.metricsGrid.innerHTML = range.metrics
      .map(function (metric, index) {
        var delta = describeChange(metric.change, metric.changeUnit);
        var tone = toneForMetric(metric);
        var labelId = "metric-label-" + metric.id;
        return (
          '<article class="metric-card" aria-labelledby="' +
          labelId +
          '">' +
          '<div class="metric-head">' +
          '<h3 class="metric-label" id="' +
          labelId +
          '">' +
          metric.label +
          "</h3>" +
          '<span class="metric-index" aria-hidden="true">' +
          String(index + 1).padStart(2, "0") +
          "</span>" +
          "</div>" +
          '<div class="metric-main">' +
          '<p class="metric-value">' +
          formatMetricValue(metric) +
          "</p>" +
          sparklineMarkup(metric.spark) +
          "</div>" +
          '<div class="metric-foot">' +
          '<span class="delta delta--' +
          tone +
          '">' +
          '<span class="delta-arrow" aria-hidden="true">' +
          delta.arrow +
          "</span>" +
          '<span aria-hidden="true">' +
          delta.display +
          "</span>" +
          '<span class="sr-only">' +
          range.compareLabel +
          " " +
          delta.spoken +
          "</span>" +
          "</span>" +
          '<span class="metric-compare" aria-hidden="true">' +
          range.compareLabel +
          "</span>" +
          "</div>" +
          "</article>"
        );
      })
      .join("");
  }

  function revenueTotal(range) {
    return range.revenue.points.reduce(function (sum, point) {
      return sum + point.value;
    }, 0);
  }

  function chooseChartScale(maximumValue) {
    var padded = maximumValue * 1.08;
    var rawStep = padded / 4;
    var magnitude = Math.pow(10, Math.floor(Math.log10(rawStep)));
    var candidates = [0.5, 1, 1.5, 2, 2.5, 3, 4, 5, 7.5, 10].map(function (factor) {
      return factor * magnitude;
    });
    var chosen = null;

    for (var index = 0; index < candidates.length; index += 1) {
      var candidate = candidates[index];
      var intervals = Math.ceil(padded / candidate);
      if (intervals >= 3 && intervals <= 5) {
        chosen = { step: candidate, intervals: intervals };
        break;
      }
    }

    if (!chosen) {
      var fallback = candidates.find(function (candidate) {
        return Math.ceil(padded / candidate) <= 5;
      });
      var step = fallback || magnitude * 10;
      chosen = { step: step, intervals: Math.max(3, Math.ceil(padded / step)) };
    }

    return {
      step: chosen.step,
      intervals: chosen.intervals,
      max: chosen.step * chosen.intervals
    };
  }

  function renderRevenueHeader(range) {
    var total = revenueTotal(range);
    var change = ((total - range.revenue.previousTotal) / range.revenue.previousTotal) * 100;
    var delta = describeChange(change, "%");
    var tone = change === 0 ? "neutral" : change > 0 ? "good" : "bad";

    elements.revenueSubtitle.textContent = range.granularity + " · 演示数据";
    elements.revenueTotal.textContent = formatCurrency(total);
    elements.chartPointsNote.textContent = range.revenue.points.length + " 个数据点";
    elements.revenueChange.className = "delta delta--" + tone;
    elements.revenueChange.innerHTML =
      '<span aria-hidden="true"><span class="delta-arrow">' +
      delta.arrow +
      "</span> " +
      decimalFormat.format(Math.abs(change)) +
      "%</span>" +
      '<span class="sr-only">' +
      range.compareLabel +
      " " +
      delta.spoken +
      "</span>";
    elements.revenueTableCaption.textContent =
      range.label + "收入趋势（本地演示数据，单位：元）";
    elements.revenueTableBody.innerHTML = range.revenue.points
      .map(function (point) {
        return (
          "<tr><td>" +
          point.date +
          '</td><td class="numeric">' +
          numberFormat.format(point.value) +
          "</td></tr>"
        );
      })
      .join("");

    var values = range.revenue.points.map(function (point) {
      return point.value;
    });
    elements.revenueChartSummary.textContent =
      range.label +
      "（" +
      range.start +
      " 至 " +
      range.end +
      "）收入趋势图，共 " +
      range.revenue.points.length +
      " 个数据点。最低 " +
      formatCurrency(Math.min.apply(null, values)) +
      "，最高 " +
      formatCurrency(Math.max.apply(null, values)) +
      "。完整数值可在数据表中查看。";
  }

  function chartAxisLabel(value) {
    if (value === 0) return "¥0";
    if (value >= 1000) return "¥" + trimDecimal(value / 1000) + "k";
    return "¥" + numberFormat.format(value);
  }

  function renderRevenueChart() {
    var range = currentRange();
    var wrap = elements.revenueChartWrap;
    if (!wrap) return;

    var width = Math.max(200, Math.floor(wrap.clientWidth || 640));
    lastChartWidth = width;
    var height = width < 440 ? 200 : width < 700 ? 238 : 264;
    var margin = { top: 12, right: 22, bottom: 27, left: 47 };
    var innerWidth = Math.max(40, width - margin.left - margin.right);
    var innerHeight = Math.max(40, height - margin.top - margin.bottom);
    var points = range.revenue.points;
    var values = points.map(function (point) {
      return point.value;
    });
    var scale = chooseChartScale(Math.max.apply(null, values));
    var geometry = points.map(function (point, index) {
      var x =
        margin.left + (index / Math.max(1, points.length - 1)) * Math.max(1, innerWidth);
      var y = margin.top + innerHeight - (point.value / scale.max) * innerHeight;
      return { x: x, y: y, point: point };
    });

    var linePath = geometry
      .map(function (point, index) {
        return (index === 0 ? "M" : "L") + point.x.toFixed(2) + " " + point.y.toFixed(2);
      })
      .join(" ");
    var firstPoint = geometry[0];
    var lastPoint = geometry[geometry.length - 1];
    var baseline = margin.top + innerHeight;
    var areaPath =
      "M" +
      firstPoint.x.toFixed(2) +
      " " +
      baseline.toFixed(2) +
      " L" +
      geometry
        .map(function (point) {
          return point.x.toFixed(2) + " " + point.y.toFixed(2);
        })
        .join(" L") +
      " L" +
      lastPoint.x.toFixed(2) +
      " " +
      baseline.toFixed(2) +
      " Z";

    var gridMarkup = "";
    for (var tick = 0; tick <= scale.intervals; tick += 1) {
      var tickValue = tick * scale.step;
      var tickY = margin.top + innerHeight - (tickValue / scale.max) * innerHeight;
      gridMarkup +=
        '<line class="' +
        (tick === 0 ? "chart-baseline" : "chart-grid-line") +
        '" x1="' +
        margin.left +
        '" y1="' +
        tickY.toFixed(2) +
        '" x2="' +
        (margin.left + innerWidth) +
        '" y2="' +
        tickY.toFixed(2) +
        '"></line>' +
        '<text class="chart-axis-label" x="' +
        (margin.left - 8) +
        '" y="' +
        (tickY + 3).toFixed(2) +
        '" text-anchor="end">' +
        chartAxisLabel(tickValue) +
        "</text>";
    }

    var maximumLabels = Math.max(2, Math.min(points.length, Math.floor(innerWidth / 70)));
    var labelIndices = [];
    for (var index = 0; index < maximumLabels; index += 1) {
      var pointIndex =
        maximumLabels === 1
          ? 0
          : Math.round((index / (maximumLabels - 1)) * (points.length - 1));
      if (labelIndices.indexOf(pointIndex) === -1) labelIndices.push(pointIndex);
    }

    var xLabelsMarkup = labelIndices
      .map(function (pointIndex) {
        var point = geometry[pointIndex];
        return (
          '<text class="chart-axis-label" x="' +
          point.x.toFixed(2) +
          '" y="' +
          (height - 8) +
          '" text-anchor="middle">' +
          point.point.label +
          "</text>"
        );
      })
      .join("");

    wrap.innerHTML =
      '<svg class="revenue-svg" viewBox="0 0 ' +
      width +
      " " +
      height +
      '" width="' +
      width +
      '" height="' +
      height +
      '" role="img" aria-labelledby="revenue-title" aria-describedby="revenue-chart-summary">' +
      "<defs>" +
      '<linearGradient id="revenue-area-gradient" x1="0" y1="0" x2="0" y2="1">' +
      '<stop offset="0%" stop-color="#5b6c49" stop-opacity="0.2"></stop>' +
      '<stop offset="100%" stop-color="#5b6c49" stop-opacity="0"></stop>' +
      "</linearGradient>" +
      "</defs>" +
      gridMarkup +
      xLabelsMarkup +
      '<path class="chart-area" fill="url(#revenue-area-gradient)" d="' +
      areaPath +
      '"></path>' +
      '<path class="chart-line" d="' +
      linePath +
      '"></path>' +
      '<circle class="chart-endpoint-halo" cx="' +
      lastPoint.x.toFixed(2) +
      '" cy="' +
      lastPoint.y.toFixed(2) +
      '" r="7"></circle>' +
      '<circle class="chart-endpoint" cx="' +
      lastPoint.x.toFixed(2) +
      '" cy="' +
      lastPoint.y.toFixed(2) +
      '" r="3.3"></circle>' +
      '<g class="chart-hover" visibility="hidden" aria-hidden="true">' +
      '<line class="chart-cursor" y1="' +
      margin.top +
      '" y2="' +
      baseline +
      '"></line>' +
      '<circle class="chart-cursor-dot" r="3.6"></circle>' +
      "</g>" +
      '<rect class="chart-hit" x="' +
      margin.left +
      '" y="' +
      margin.top +
      '" width="' +
      innerWidth +
      '" height="' +
      innerHeight +
      '" fill="transparent"></rect>' +
      "</svg>";

    elements.chartTooltip.hidden = true;
    bindChartPointer(geometry, {
      width: width,
      height: height,
      margin: margin,
      innerWidth: innerWidth
    });
  }

  function bindChartPointer(geometry, metrics) {
    var svg = elements.revenueChartWrap.querySelector("svg");
    if (!svg) return;
    var hover = svg.querySelector(".chart-hover");
    var cursorLine = svg.querySelector(".chart-cursor");
    var cursorDot = svg.querySelector(".chart-cursor-dot");
    var tooltip = elements.chartTooltip;

    function hideTooltip() {
      tooltip.hidden = true;
      hover.setAttribute("visibility", "hidden");
    }

    function handlePointerMove(event) {
      var svgRect = svg.getBoundingClientRect();
      if (!svgRect.width) return;
      var localX = ((event.clientX - svgRect.left) / svgRect.width) * metrics.width;
      var ratio = (localX - metrics.margin.left) / Math.max(1, metrics.innerWidth);
      var index = Math.round(ratio * (geometry.length - 1));
      index = Math.max(0, Math.min(geometry.length - 1, index));
      var target = geometry[index];

      cursorLine.setAttribute("x1", target.x);
      cursorLine.setAttribute("x2", target.x);
      cursorDot.setAttribute("cx", target.x);
      cursorDot.setAttribute("cy", target.y);
      hover.setAttribute("visibility", "visible");

      tooltip.innerHTML =
        '<span class="chart-tip-date">' +
        target.point.date +
        '</span><span class="chart-tip-value">' +
        formatCurrency(target.point.value) +
        "</span>";
      tooltip.hidden = false;

      var shellRect = elements.revenueChartShell.getBoundingClientRect();
      var pointX = svgRect.left - shellRect.left + target.x * (svgRect.width / metrics.width);
      var pointY = svgRect.top - shellRect.top + target.y * (svgRect.height / metrics.height);
      var tooltipHalf = Math.min(70, tooltip.offsetWidth / 2 || 60);
      var clampedX = Math.max(tooltipHalf + 6, Math.min(shellRect.width - tooltipHalf - 6, pointX));
      tooltip.style.left = clampedX + "px";
      tooltip.style.top = pointY + "px";
      tooltip.classList.toggle("is-below", pointY < 74);
    }

    svg.addEventListener("pointermove", handlePointerMove);
    svg.addEventListener("pointerleave", hideTooltip);
    svg.addEventListener("pointerdown", handlePointerMove);
  }

  function renderPlans(range) {
    var total = range.plans.reduce(function (sum, plan) {
      return sum + plan.value;
    }, 0);
    var radius = 66;
    var center = 85;
    var strokeWidth = 18;
    var circumference = 2 * Math.PI * radius;
    var gap = 3.5;
    var offset = 0;

    var segments = range.plans
      .map(function (plan) {
        var rawArc = (plan.value / total) * circumference;
        var visibleArc = Math.max(1, rawArc - gap);
        var segment =
          '<circle class="donut-segment" cx="' +
          center +
          '" cy="' +
          center +
          '" r="' +
          radius +
          '" stroke="' +
          plan.color +
          '" stroke-width="' +
          strokeWidth +
          '" stroke-dasharray="' +
          visibleArc.toFixed(2) +
          " " +
          circumference.toFixed(2) +
          '" stroke-dashoffset="' +
          (-offset).toFixed(2) +
          '"></circle>';
        offset += rawArc;
        return segment;
      })
      .join("");

    elements.planDonut.innerHTML =
      '<circle class="donut-track" cx="' +
      center +
      '" cy="' +
      center +
      '" r="' +
      radius +
      '" stroke-width="' +
      strokeWidth +
      '"></circle>' +
      segments;
    elements.planTotal.textContent = formatCompactCurrency(total);
    elements.planList.innerHTML = range.plans
      .map(function (plan) {
        var share = ((plan.value / total) * 100).toFixed(1);
        return (
          '<li class="plan-item" style="--plan-color: ' +
          plan.color +
          '">' +
          '<span class="plan-dot" aria-hidden="true"></span>' +
          '<span class="plan-main">' +
          '<span class="plan-name">' +
          plan.name +
          "</span>" +
          '<span class="plan-value">' +
          formatCurrency(plan.value) +
          "</span>" +
          "</span>" +
          '<span class="plan-share">' +
          share +
          "%</span>" +
          "</li>"
        );
      })
      .join("");
  }

  function renderRange(range) {
    renderMetrics(range);
    renderRevenueHeader(range);
    renderPlans(range);
    window.requestAnimationFrame(renderRevenueChart);

    Array.prototype.forEach.call(elements.rangeButtons.querySelectorAll("[data-range]"), function (button) {
      var active = button.getAttribute("data-range") === range.id;
      button.classList.toggle("is-active", active);
      button.setAttribute("aria-pressed", active ? "true" : "false");
    });

    elements.rangePeriod.textContent = range.periodLabel;
    elements.rangeGranularity.textContent = range.granularity;
  }

  function updateRange(rangeId, shouldAnnounce) {
    var range = demo.ranges.find(function (item) {
      return item.id === rangeId;
    });
    if (!range || range.id === state.rangeId) return;

    state.rangeId = range.id;
    renderRange(range);
    if (shouldAnnounce) {
      announce("已切换至" + range.label + "，数据周期 " + range.periodLabel + "。");
    }
  }

  function normalized(value) {
    return String(value).toLocaleLowerCase("zh-CN");
  }

  function searchableFieldsMatch(fields, query) {
    if (!query) return true;
    var needle = normalized(query);
    return fields.some(function (field) {
      return normalized(field).indexOf(needle) !== -1;
    });
  }

  function filteredTasks() {
    return state.tasks.filter(function (task) {
      return searchableFieldsMatch(
        [task.title, task.group, task.due, task.owner, task.priority],
        state.query
      );
    });
  }

  function filteredNotifications() {
    return state.notifications.filter(function (notification) {
      return searchableFieldsMatch(
        [notification.title, notification.body, notification.tag, notification.time],
        state.query
      );
    });
  }

  function updateTaskProgress() {
    var total = state.tasks.length;
    var completed = state.tasks.filter(function (task) {
      return task.done;
    }).length;
    var percent = total ? Math.round((completed / total) * 100) : 0;

    elements.taskCount.textContent = "已完成 " + completed + " / " + total;
    elements.taskPercent.textContent = percent + "%";
    elements.taskProgress.style.width = percent + "%";
    elements.taskProgressTrack.setAttribute("aria-valuemax", String(total));
    elements.taskProgressTrack.setAttribute("aria-valuenow", String(completed));
    elements.taskProgressTrack.setAttribute("aria-valuetext", completed + " / " + total);
    elements.navTaskBadge.textContent = completed + "/" + total;
  }

  function renderTasks() {
    var tasks = filteredTasks();
    elements.taskList.innerHTML = tasks
      .map(function (task) {
        var checkboxId = "task-checkbox-" + task.id;
        var priorityClass = task.priority === "高" ? " priority--high" : "";
        return (
          '<li class="task-item' +
          (task.done ? " is-done" : "") +
          '" data-task-id="' +
          task.id +
          '">' +
          '<input class="task-checkbox" id="' +
          checkboxId +
          '" type="checkbox" data-task-id="' +
          task.id +
          '"' +
          (task.done ? " checked" : "") +
          ">" +
          '<label class="task-main" for="' +
          checkboxId +
          '">' +
          '<span class="task-title">' +
          task.title +
          "</span>" +
          '<span class="task-meta">' +
          '<span class="task-group">' +
          task.group +
          "</span>" +
          '<span class="task-meta-dot" aria-hidden="true">·</span>' +
          '<span class="task-due">' +
          task.due +
          "</span>" +
          '<span class="task-meta-dot" aria-hidden="true">·</span>' +
          '<span class="task-owner">' +
          task.owner +
          "</span>" +
          "</span>" +
          "</label>" +
          '<span class="priority' +
          priorityClass +
          '">' +
          task.priority +
          "</span>" +
          "</li>"
        );
      })
      .join("");
    elements.taskEmpty.hidden = tasks.length > 0;
    updateTaskProgress();
  }

  function updateUnreadSummary() {
    var unread = state.notifications.filter(function (notification) {
      return notification.unread;
    }).length;

    elements.unreadCount.textContent = unread === 0 ? "全部已读" : unread + " 条未读";
    elements.markAllRead.textContent = unread === 0 ? "全部已读" : "全部标为已读";

    if (unread === 0) {
      elements.markAllRead.setAttribute("aria-disabled", "true");
      elements.navUnreadBadge.hidden = true;
    } else {
      elements.markAllRead.removeAttribute("aria-disabled");
      elements.navUnreadBadge.hidden = false;
      elements.navUnreadBadge.textContent = String(unread);
    }
  }

  function renderNotifications() {
    var notifications = filteredNotifications();
    elements.notificationList.innerHTML = notifications
      .map(function (notification) {
        var unread = notification.unread;
        return (
          '<li class="notification ' +
          (unread ? "is-unread" : "is-read") +
          '" data-notification-id="' +
          notification.id +
          '">' +
          '<div class="notification-top">' +
          '<span class="notification-tag">' +
          notification.tag +
          "</span>" +
          '<span class="notification-time">' +
          (unread ? '<span class="sr-only unread-label">未读，</span>' : "") +
          notification.time +
          "</span>" +
          "</div>" +
          '<h3 class="notification-title">' +
          (unread ? '<span class="unread-dot" aria-hidden="true"></span>' : "") +
          notification.title +
          "</h3>" +
          '<p class="notification-body">' +
          notification.body +
          "</p>" +
          '<div class="notification-foot">' +
          '<button class="mark-read" type="button" data-mark-read="' +
          notification.id +
          '" aria-label="将通知“' +
          notification.title +
          '”标为已读"' +
          (unread ? "" : ' aria-disabled="true"') +
          ">" +
          (unread ? "标为已读" : "已读") +
          "</button>" +
          "</div>" +
          "</li>"
        );
      })
      .join("");
    elements.notificationEmpty.hidden = notifications.length > 0;
    updateUnreadSummary();
  }

  function updateSearchChrome() {
    var hasQuery = state.query.length > 0;
    elements.filterStrip.hidden = !hasQuery;
    elements.searchClear.hidden = elements.searchInput.value.length === 0;

    if (hasQuery) {
      elements.filterQuery.textContent = "“" + state.query + "”";
      elements.filterTaskCount.textContent = String(filteredTasks().length);
      elements.filterNotificationCount.textContent = String(filteredNotifications().length);
    }
  }

  function applyFiltering() {
    renderTasks();
    renderNotifications();
    updateSearchChrome();
  }

  function clearSearch(options) {
    var settings = options || {};
    window.clearTimeout(searchTimer);
    elements.searchInput.value = "";
    state.query = "";
    elements.searchClear.hidden = true;
    applyFiltering();
    if (settings.focus !== false) elements.searchInput.focus();
  }

  function renderTeam() {
    var online = demo.team.filter(function (member) {
      return member.status === "online";
    }).length;

    elements.teamCount.textContent = demo.team.length + " 人 · " + online + " 在线";
    elements.teamList.innerHTML = demo.team
      .map(function (member) {
        return (
          '<li class="team-item">' +
          '<span class="avatar" aria-hidden="true">' +
          member.initials +
          "</span>" +
          '<span class="team-main">' +
          '<span class="team-name">' +
          member.name +
          "</span>" +
          '<span class="team-meta"><span>' +
          member.role +
          '</span><span aria-hidden="true">·</span><span class="team-load">负荷 ' +
          member.load +
          "%</span></span>" +
          "</span>" +
          '<span class="team-status">' +
          '<span class="status-indicator status-indicator--' +
          member.status +
          '" aria-hidden="true"></span>' +
          member.statusLabel +
          "</span>" +
          "</li>"
        );
      })
      .join("");
  }

  function markNotificationRead(notification) {
    var item = elements.notificationList.querySelector(
      '[data-notification-id="' + notification.id + '"]'
    );
    if (!item) return;

    notification.unread = false;
    item.classList.remove("is-unread");
    item.classList.add("is-read");
    var dot = item.querySelector(".unread-dot");
    if (dot) dot.remove();
    var unreadLabel = item.querySelector(".unread-label");
    if (unreadLabel) unreadLabel.remove();
    var button = item.querySelector(".mark-read");
    if (button) {
      button.textContent = "已读";
      button.setAttribute("aria-disabled", "true");
      button.setAttribute("aria-label", "通知“" + notification.title + "”已读");
    }
  }

  function csvCell(value) {
    var text = String(value == null ? "" : value);
    if (/[",\r\n]/.test(text)) {
      return '"' + text.replace(/"/g, '""') + '"';
    }
    return text;
  }

  function csvRow(cells) {
    return cells.map(csvCell).join(",");
  }

  function buildCsv(range) {
    var lines = [];
    var total = revenueTotal(range);
    var metricUnit = function (metric) {
      if (metric.kind === "currency") return "元";
      if (metric.kind === "integer") return "人";
      return "%";
    };

    lines.push(csvRow(["Citro 增长分析工作台 · 本地演示数据"]));
    lines.push(csvRow(["数据范围", demo.scope + "（虚构演示数据）"]));
    lines.push(csvRow(["时间范围", range.label + "（" + range.start + " 至 " + range.end + "）"]));
    lines.push(csvRow(["导出时间", new Intl.DateTimeFormat("zh-CN", { dateStyle: "medium", timeStyle: "short" }).format(new Date())]));
    lines.push(csvRow(["说明", demo.disclaimer]));
    lines.push(csvRow(["导出内容", "仅包含当前时间范围的分析数据；任务与通知不随时间范围变化。"]));
    lines.push("");
    lines.push(csvRow(["指标", "数值", "数值单位", "变化值", "变化单位", "比较基准"]));
    range.metrics.forEach(function (metric) {
      lines.push(
        csvRow([
          metric.label,
          metric.value,
          metricUnit(metric),
          metric.change,
          metric.changeUnit,
          range.compareLabel
        ])
      );
    });
    lines.push("");
    lines.push(csvRow(["收入趋势", "区间收入合计", total, "元"]));
    lines.push(csvRow(["日期", "收入（元）"]));
    range.revenue.points.forEach(function (point) {
      lines.push(csvRow([point.date, point.value]));
    });
    lines.push("");
    lines.push(csvRow(["套餐", "MRR（元）", "占比"]));
    var planTotal = range.plans.reduce(function (sum, plan) {
      return sum + plan.value;
    }, 0);
    range.plans.forEach(function (plan) {
      lines.push(
        csvRow([plan.name, plan.value, ((plan.value / planTotal) * 100).toFixed(1) + "%"])
      );
    });
    return "\ufeff" + lines.join("\r\n") + "\r\n";
  }

  function exportCsv() {
    var range = currentRange();
    var blob = new Blob([buildCsv(range)], { type: "text/csv;charset=utf-8;" });
    var url = URL.createObjectURL(blob);
    var link = document.createElement("a");
    link.href = url;
    link.download = "citro-demo_" + range.id + "_" + demo.demoAsOf + ".csv";
    document.body.appendChild(link);
    link.click();
    link.remove();
    window.setTimeout(function () {
      URL.revokeObjectURL(url);
    }, 60000);
    showToast("已导出" + range.label + "演示数据 CSV。");
  }

  function openDataDialog() {
    if (drawerOpen) closeDrawer();
    if (typeof elements.dataDialog.showModal === "function") {
      elements.dataDialog.showModal();
    } else {
      elements.dataDialog.setAttribute("open", "");
    }
  }

  function closeDataDialog() {
    if (typeof elements.dataDialog.close === "function") {
      elements.dataDialog.close();
    } else {
      elements.dataDialog.removeAttribute("open");
    }
  }

  function setActiveNav(sectionId) {
    elements.navLinks.forEach(function (link) {
      var active = link.getAttribute("data-section") === sectionId;
      link.classList.toggle("is-active", active);
      if (active) {
        link.setAttribute("aria-current", "page");
      } else {
        link.removeAttribute("aria-current");
      }
    });
  }

  function focusSectionHeading(sectionId) {
    var section = document.getElementById(sectionId);
    if (!section) return;
    var heading = section.querySelector("h1, h2");
    if (!heading) return;
    heading.setAttribute("tabindex", "-1");
    window.setTimeout(function () {
      heading.focus({ preventScroll: true });
    }, 0);
  }

  function drawerFocusable() {
    return Array.prototype.slice
      .call(
        elements.sidebar.querySelectorAll(
          'a[href], button:not([disabled]), input:not([disabled]), [tabindex]:not([tabindex="-1"])'
        )
      )
      .filter(function (element) {
        return element.getClientRects().length > 0;
      });
  }

  function openDrawer() {
    if (!mobileQuery.matches || drawerOpen) return;
    drawerOpen = true;
    elements.sidebar.removeAttribute("inert");
    elements.workspaceColumn.setAttribute("inert", "");
    document.body.classList.add("nav-open");
    elements.navScrim.hidden = false;
    elements.menuButton.setAttribute("aria-expanded", "true");
    window.requestAnimationFrame(function () {
      elements.drawerClose.focus();
    });
  }

  function closeDrawer(options) {
    var settings = options || {};
    if (!drawerOpen) {
      if (mobileQuery.matches) elements.sidebar.setAttribute("inert", "");
      elements.workspaceColumn.removeAttribute("inert");
      return;
    }
    drawerOpen = false;
    document.body.classList.remove("nav-open");
    elements.navScrim.hidden = true;
    elements.menuButton.setAttribute("aria-expanded", "false");
    elements.sidebar.setAttribute("inert", "");
    elements.workspaceColumn.removeAttribute("inert");
    if (settings.restoreFocus !== false) elements.menuButton.focus();
  }

  function syncDrawerMode() {
    if (mobileQuery.matches) {
      if (!drawerOpen) elements.sidebar.setAttribute("inert", "");
      elements.navScrim.hidden = true;
    } else {
      drawerOpen = false;
      document.body.classList.remove("nav-open");
      elements.navScrim.hidden = true;
      elements.sidebar.removeAttribute("inert");
      elements.workspaceColumn.removeAttribute("inert");
      elements.menuButton.setAttribute("aria-expanded", "false");
    }
  }

  function setDemoDates() {
    Array.prototype.forEach.call(document.querySelectorAll("[data-demo-date]"), function (node) {
      node.textContent = demo.demoAsOf;
      if (node.tagName === "TIME") node.setAttribute("datetime", demo.demoAsOf);
    });
  }

  function bindEvents() {
    elements.rangeButtons.addEventListener("click", function (event) {
      var button = event.target.closest("[data-range]");
      if (!button) return;
      updateRange(button.getAttribute("data-range"), true);
    });

    elements.exportButton.addEventListener("click", exportCsv);

    elements.searchForm.addEventListener("submit", function (event) {
      event.preventDefault();
      window.clearTimeout(searchTimer);
      state.query = elements.searchInput.value.trim();
      applyFiltering();
    });

    elements.searchInput.addEventListener("input", function () {
      elements.searchClear.hidden = elements.searchInput.value.trim().length === 0;
      window.clearTimeout(searchTimer);
      searchTimer = window.setTimeout(function () {
        state.query = elements.searchInput.value.trim();
        applyFiltering();
      }, 130);
    });

    elements.searchInput.addEventListener("keydown", function (event) {
      if (event.key === "Escape" && elements.searchInput.value) {
        event.preventDefault();
        clearSearch();
      }
    });

    elements.searchClear.addEventListener("click", function () {
      clearSearch();
    });

    elements.filterClear.addEventListener("click", function () {
      clearSearch();
    });

    elements.taskEmptyClear.addEventListener("click", function () {
      clearSearch();
    });

    elements.notificationEmptyClear.addEventListener("click", function () {
      clearSearch();
    });

    elements.taskList.addEventListener("change", function (event) {
      var checkbox = event.target.closest(".task-checkbox");
      if (!checkbox) return;
      var taskId = checkbox.getAttribute("data-task-id");
      var task = state.tasks.find(function (item) {
        return item.id === taskId;
      });
      if (!task) return;
      task.done = checkbox.checked;
      var item = checkbox.closest(".task-item");
      if (item) item.classList.toggle("is-done", task.done);
      updateTaskProgress();
      var completed = state.tasks.filter(function (entry) {
        return entry.done;
      }).length;
      announce(
        (task.done ? "已完成：" : "已重新打开：") +
          task.title +
          "。当前完成 " +
          completed +
          " / " +
          state.tasks.length +
          " 项。"
      );
    });

    elements.notificationList.addEventListener("click", function (event) {
      var button = event.target.closest("[data-mark-read]");
      if (!button || button.getAttribute("aria-disabled") === "true") return;
      var notificationId = button.getAttribute("data-mark-read");
      var notification = state.notifications.find(function (item) {
        return item.id === notificationId;
      });
      if (!notification || !notification.unread) return;
      markNotificationRead(notification);
      updateUnreadSummary();
      var unread = state.notifications.filter(function (item) {
        return item.unread;
      }).length;
      announce(
        "已将通知“" +
          notification.title +
          "”标为已读。" +
          (unread === 0 ? "全部通知已读。" : "还有 " + unread + " 条未读。")
      );
    });

    elements.markAllRead.addEventListener("click", function () {
      if (elements.markAllRead.getAttribute("aria-disabled") === "true") return;
      var unread = state.notifications.filter(function (notification) {
        return notification.unread;
      });
      if (!unread.length) return;
      state.notifications.forEach(function (notification) {
        if (!notification.unread) return;
        notification.unread = false;
      });
      Array.prototype.forEach.call(
        elements.notificationList.querySelectorAll(".notification"),
        function (item) {
          var notification = state.notifications.find(function (entry) {
            return entry.id === item.getAttribute("data-notification-id");
          });
          if (notification) markNotificationRead(notification);
        }
      );
      renderNotifications();
      announce("已将全部通知标为已读。");
    });

    elements.menuButton.addEventListener("click", openDrawer);
    elements.drawerClose.addEventListener("click", function () {
      closeDrawer();
    });
    elements.navScrim.addEventListener("click", function () {
      closeDrawer();
    });

    Array.prototype.forEach.call(
      elements.sidebar.querySelectorAll(".nav-link[data-section]"),
      function (link) {
        link.addEventListener("click", function () {
          setActiveNav(link.getAttribute("data-section"));
          if (mobileQuery.matches) closeDrawer({ restoreFocus: false });
          focusSectionHeading(link.getAttribute("data-section"));
        });
      }
    );

    var brandLink = elements.sidebar.querySelector(".brand");
    if (brandLink) {
      brandLink.addEventListener("click", function () {
        setActiveNav("overview");
        if (mobileQuery.matches) closeDrawer({ restoreFocus: false });
        focusSectionHeading("overview");
      });
    }

    Array.prototype.forEach.call(document.querySelectorAll("[data-open-notes]"), function (button) {
      button.addEventListener("click", openDataDialog);
    });

    elements.dialogClose.addEventListener("click", closeDataDialog);
    elements.dialogDone.addEventListener("click", closeDataDialog);
    elements.dataDialog.addEventListener("click", function (event) {
      if (event.target !== elements.dataDialog) return;
      var rect = elements.dataDialog.getBoundingClientRect();
      var outside =
        event.clientX < rect.left ||
        event.clientX > rect.right ||
        event.clientY < rect.top ||
        event.clientY > rect.bottom;
      if (outside) closeDataDialog();
    });

    document.addEventListener("keydown", function (event) {
      if (!drawerOpen) return;
      if (event.key === "Escape") {
        event.preventDefault();
        closeDrawer();
        return;
      }
      if (event.key !== "Tab") return;
      var focusable = drawerFocusable();
      if (!focusable.length) return;
      var first = focusable[0];
      var last = focusable[focusable.length - 1];
      if (event.shiftKey) {
        if (document.activeElement === first || !elements.sidebar.contains(document.activeElement)) {
          event.preventDefault();
          last.focus();
        }
      } else if (document.activeElement === last) {
        event.preventDefault();
        first.focus();
      }
    });

    if (typeof mobileQuery.addEventListener === "function") {
      mobileQuery.addEventListener("change", syncDrawerMode);
    } else if (typeof mobileQuery.addListener === "function") {
      mobileQuery.addListener(syncDrawerMode);
    }
  }

  function initChartResize() {
    if (typeof ResizeObserver !== "function") {
      window.addEventListener("resize", function () {
        window.cancelAnimationFrame(chartResizeFrame);
        chartResizeFrame = window.requestAnimationFrame(renderRevenueChart);
      });
      return;
    }

    var observer = new ResizeObserver(function () {
      var width = Math.floor(elements.revenueChartWrap.clientWidth);
      if (!width || Math.abs(width - lastChartWidth) < 1) return;
      window.cancelAnimationFrame(chartResizeFrame);
      chartResizeFrame = window.requestAnimationFrame(renderRevenueChart);
    });
    observer.observe(elements.revenueChartWrap);
  }

  function init() {
    setDemoDates();
    renderTeam();
    renderRange(currentRange());
    renderTasks();
    renderNotifications();
    updateSearchChrome();
    syncDrawerMode();
    bindEvents();
    initChartResize();
  }

  if (document.readyState === "loading") {
    document.addEventListener("DOMContentLoaded", init);
  } else {
    init();
  }
})();
