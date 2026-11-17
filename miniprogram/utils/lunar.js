// 农历 / 二十四节气 / 常见节日 · 纯离线查表实现
//
// 农历压缩表覆盖 1900–2100 年。每个年份用一个整数表示：
//   bit 16     闰月大小（1 = 30 天，0 = 29 天）
//   bit 15..4  正月至腊月的大小月（1 = 30 天，0 = 29 天）
//   bit 3..0   闰月月份（0 表示该年无闰月）
// 数据取自公开的 1900–2100 农历压缩表（jjonline/calendar.js 一脉，
// 与香港天文台公布的农历数据逐年核对过），与 Flutter 端 utils/lunar.dart
// 的节日命名保持一致。
//
// 节气用常见的「寿星公式」近似到日：
//   day = Date(31556925974.7 * (year - 1900) + termMinutes[i] * 60000
//              + Date.UTC(1900, 0, 6, 2, 5)).getUTCDate()
// 该公式在 1900–2100 年与官方交节日期基本一致，个别年份可能相差一天；
// 页面只用它做当日节气标签，不参与任何日期计算。
//
// 所有导出函数对非法 / 超范围日期都返回空字符串，不抛异常。

const LUNAR_INFO = [
  0x04bd8, 0x04ae0, 0x0a570, 0x054d5, 0x0d260, 0x0d950, 0x16554, 0x056a0,
  0x09ad0, 0x055d2, // 1900-1909
  0x04ae0, 0x0a5b6, 0x0a4d0, 0x0d250, 0x1d255, 0x0b540, 0x0d6a0, 0x0ada2,
  0x095b0, 0x14977, // 1910-1919
  0x04970, 0x0a4b0, 0x0b4b5, 0x06a50, 0x06d40, 0x1ab54, 0x02b60, 0x09570,
  0x052f2, 0x04970, // 1920-1929
  0x06566, 0x0d4a0, 0x0ea50, 0x06e95, 0x05ad0, 0x02b60, 0x186e3, 0x092e0,
  0x1c8d7, 0x0c950, // 1930-1939
  0x0d4a0, 0x1d8a6, 0x0b550, 0x056a0, 0x1a5b4, 0x025d0, 0x092d0, 0x0d2b2,
  0x0a950, 0x0b557, // 1940-1949
  0x06ca0, 0x0b550, 0x15355, 0x04da0, 0x0a5b0, 0x14573, 0x052b0, 0x0a9a8,
  0x0e950, 0x06aa0, // 1950-1959
  0x0aea6, 0x0ab50, 0x04b60, 0x0aae4, 0x0a570, 0x05260, 0x0f263, 0x0d950,
  0x05b57, 0x056a0, // 1960-1969
  0x096d0, 0x04dd5, 0x04ad0, 0x0a4d0, 0x0d4d4, 0x0d250, 0x0d558, 0x0b540,
  0x0b5a0, 0x195a6, // 1970-1979
  0x095b0, 0x049b0, 0x0a974, 0x0a4b0, 0x0b27a, 0x06a50, 0x06d40, 0x0af46,
  0x0ab60, 0x09570, // 1980-1989
  0x04af5, 0x04970, 0x064b0, 0x074a3, 0x0ea50, 0x06b58, 0x05ac0, 0x0ab60,
  0x096d5, 0x092e0, // 1990-1999
  0x0c960, 0x0d954, 0x0d4a0, 0x0da50, 0x07552, 0x056a0, 0x0abb7, 0x025d0,
  0x092d0, 0x0cab5, // 2000-2009
  0x0a950, 0x0b4a0, 0x0baa4, 0x0ad50, 0x055d9, 0x04ba0, 0x0a5b0, 0x15176,
  0x052b0, 0x0a930, // 2010-2019
  0x07954, 0x06aa0, 0x0ad50, 0x05b52, 0x04b60, 0x0a6e6, 0x0a4e0, 0x0d260,
  0x0ea65, 0x0d530, // 2020-2029
  0x05aa0, 0x076a3, 0x096d0, 0x04afb, 0x04ad0, 0x0a4d0, 0x1d0b6, 0x0d250,
  0x0d520, 0x0dd45, // 2030-2039
  0x0b5a0, 0x056d0, 0x055b2, 0x049b0, 0x0a577, 0x0a4b0, 0x0aa50, 0x1b255,
  0x06d20, 0x0ada0, // 2040-2049
  0x14b63, 0x09370, 0x049f8, 0x04970, 0x064b0, 0x168a6, 0x0ea50, 0x06b20,
  0x1a6c4, 0x0aae0, // 2050-2059
  0x0a2e0, 0x0d2e3, 0x0c960, 0x0d557, 0x0d4a0, 0x0da50, 0x05d55, 0x056a0,
  0x0a6d0, 0x055d4, // 2060-2069
  0x052d0, 0x0a9b8, 0x0a950, 0x0b4a0, 0x0b6a6, 0x0ad50, 0x055a0, 0x0aba4,
  0x0a5b0, 0x052b0, // 2070-2079
  0x0b273, 0x06930, 0x07337, 0x06aa0, 0x0ad50, 0x14b55, 0x04b60, 0x0a570,
  0x054e4, 0x0d160, // 2080-2089
  0x0e968, 0x0d520, 0x0daa0, 0x16aa6, 0x056d0, 0x04ae0, 0x0a9d4, 0x0a2d0,
  0x0d150, 0x0f252, // 2090-2099
  0x0d520, // 2100
];

const LUNAR_MONTH_NAMES = [
  "正月",
  "二月",
  "三月",
  "四月",
  "五月",
  "六月",
  "七月",
  "八月",
  "九月",
  "十月",
  "冬月",
  "腊月",
];

const LUNAR_DAY_NAMES = [
  "初一",
  "初二",
  "初三",
  "初四",
  "初五",
  "初六",
  "初七",
  "初八",
  "初九",
  "初十",
  "十一",
  "十二",
  "十三",
  "十四",
  "十五",
  "十六",
  "十七",
  "十八",
  "十九",
  "二十",
  "廿一",
  "廿二",
  "廿三",
  "廿四",
  "廿五",
  "廿六",
  "廿七",
  "廿八",
  "廿九",
  "三十",
];

const TERM_NAMES = [
  "小寒",
  "大寒",
  "立春",
  "雨水",
  "惊蛰",
  "春分",
  "清明",
  "谷雨",
  "立夏",
  "小满",
  "芒种",
  "夏至",
  "小暑",
  "大暑",
  "立秋",
  "处暑",
  "白露",
  "秋分",
  "寒露",
  "霜降",
  "立冬",
  "小雪",
  "大雪",
  "冬至",
];

// 每个节气相对 1900-01-06 02:05 的分钟偏移（寿星公式通用表）。
const TERM_MINUTES = [
  0, 21208, 42467, 63836, 85337, 107014, 128867, 150921, 173149, 195551,
  218072, 240693, 263343, 285989, 308563, 331033, 353350, 375494, 397447,
  419210, 440795, 462224, 483532, 504758,
];

const SOLAR_FESTIVALS = {
  "01-01": "元旦",
  "02-14": "情人节",
  "03-08": "妇女节",
  "05-01": "劳动节",
  "06-01": "儿童节",
  "10-01": "国庆节",
  "12-25": "圣诞节",
};

// 农历节日按「月-日」索引；闰月不重复过节。
const LUNAR_FESTIVALS = {
  "1-1": "春节",
  "1-15": "元宵节",
  "2-2": "龙抬头",
  "5-5": "端午节",
  "7-7": "七夕节",
  "7-15": "中元节",
  "8-15": "中秋节",
  "9-9": "重阳节",
  "12-8": "腊八节",
  "12-23": "小年",
};

const DAY_MS = 86400000;
const LUNAR_BASE_DAY = Math.floor(Date.UTC(1900, 0, 31) / DAY_MS);

/* ---------------- 日期 / 农历基础计算 ---------------- */

function pad2(n) {
  return n < 10 ? "0" + n : String(n);
}

// 统一取「本地年月日」。字符串按 YYYY-MM-DD 直接解析，避免 UTC 偏移。
function partsOf(value) {
  try {
    if (value === undefined || value === null || value === "") return null;
    let d = null;
    if (value instanceof Date) {
      d = value;
    } else if (typeof value === "number") {
      d = new Date(value);
    } else if (typeof value === "string") {
      const m = /^(\d{4})-(\d{1,2})-(\d{1,2})/.exec(value.trim());
      if (m) {
        const y = Number(m[1]);
        const mo = Number(m[2]);
        const da = Number(m[3]);
        const probe = new Date(y, mo - 1, da);
        if (
          probe.getFullYear() !== y ||
          probe.getMonth() !== mo - 1 ||
          probe.getDate() !== da
        ) {
          return null;
        }
        return { y: y, m: mo, d: da };
      }
      d = new Date(value);
    } else {
      return null;
    }
    if (!d || isNaN(d.getTime())) return null;
    return { y: d.getFullYear(), m: d.getMonth() + 1, d: d.getDate() };
  } catch (e) {
    return null;
  }
}

function dayNumber(p) {
  return Math.floor(Date.UTC(p.y, p.m - 1, p.d) / DAY_MS);
}

function ymd(p) {
  return p.y + "-" + pad2(p.m) + "-" + pad2(p.d);
}

function lunarInfo(year) {
  return LUNAR_INFO[year - 1900];
}

function leapMonth(year) {
  return lunarInfo(year) & 0xf;
}

function leapDays(year) {
  if (!leapMonth(year)) return 0;
  return lunarInfo(year) & 0x10000 ? 30 : 29;
}

function monthDays(year, month) {
  return lunarInfo(year) & (0x10000 >> month) ? 30 : 29;
}

function lunarYearDays(year) {
  let sum = 348; // 12 个月都按 29 天起步
  const info = lunarInfo(year);
  for (let bit = 0x8000; bit > 0x8; bit >>= 1) {
    if (info & bit) sum += 1;
  }
  return sum + leapDays(year);
}

// 公历 -> 农历。超出 1900-01-31 ~ 2100 农历年范围时返回 null。
function lunarParts(p) {
  if (!p || p.y < 1900 || p.y > 2100) return null;
  let offset = dayNumber(p) - LUNAR_BASE_DAY;
  if (offset < 0) return null;

  let year = 1900;
  let temp = 0;
  for (; year <= 2100 && offset > 0; year++) {
    temp = lunarYearDays(year);
    offset -= temp;
  }
  if (offset < 0) {
    offset += temp;
    year--;
  }
  // 跨过表尾（2101 年及以后）时，offset 仍为正，放弃计算。
  if (year < 1900 || year > 2100) return null;

  const leap = leapMonth(year);
  let isLeap = false;
  let month = 1;
  for (month = 1; month < 13 && offset > 0; month++) {
    if (leap > 0 && month === leap + 1 && !isLeap) {
      month--;
      isLeap = true;
      temp = leapDays(year);
    } else {
      temp = monthDays(year, month);
    }
    if (isLeap && month === leap + 1) isLeap = false;
    offset -= temp;
  }
  if (offset === 0 && leap > 0 && month === leap + 1) {
    if (isLeap) {
      isLeap = false;
    } else {
      isLeap = true;
      month--;
    }
  }
  if (offset < 0) {
    offset += temp;
    month--;
  }

  const day = offset + 1;
  if (month < 1 || month > 12 || day < 1 || day > 30) return null;
  return {
    year: year,
    month: month,
    day: day,
    leap: isLeap,
    text:
      (isLeap ? "闰" : "") +
      LUNAR_MONTH_NAMES[month - 1] +
      LUNAR_DAY_NAMES[day - 1],
  };
}

function termDayOfMonth(year, index) {
  const ms =
    31556925974.7 * (year - 1900) +
    TERM_MINUTES[index] * 60000 +
    Date.UTC(1900, 0, 6, 2, 5);
  return new Date(ms).getUTCDate();
}

function termOfParts(p) {
  if (!p || p.y < 1900 || p.y > 2100) return "";
  const first = (p.m - 1) * 2;
  if (termDayOfMonth(p.y, first) === p.d) return TERM_NAMES[first];
  if (termDayOfMonth(p.y, first + 1) === p.d) return TERM_NAMES[first + 1];
  return "";
}

function festivalOfParts(p, lunar) {
  if (!p) return "";
  // 清明按节气定日。
  if (termOfParts(p) === "清明") return "清明节";

  if (lunar && !lunar.leap) {
    const lunarKey = lunar.month + "-" + lunar.day;
    if (Object.prototype.hasOwnProperty.call(LUNAR_FESTIVALS, lunarKey)) {
      return LUNAR_FESTIVALS[lunarKey];
    }
    // 除夕：腊月的最后一天（有三十则三十，否则廿九）。
    if (lunar.month === 12 && lunar.day === monthDays(lunar.year, 12)) {
      return "除夕";
    }
  }

  const solarKey = pad2(p.m) + "-" + pad2(p.d);
  if (Object.prototype.hasOwnProperty.call(SOLAR_FESTIVALS, solarKey)) {
    return SOLAR_FESTIVALS[solarKey];
  }
  return "";
}

/* ---------------- 对外接口 ---------------- */

function lunarText(date) {
  try {
    const lunar = lunarParts(partsOf(date));
    return lunar ? lunar.text : "";
  } catch (e) {
    return "";
  }
}

function solarTerm(date) {
  try {
    return termOfParts(partsOf(date)) || "";
  } catch (e) {
    return "";
  }
}

function festival(date) {
  try {
    const p = partsOf(date);
    if (!p) return "";
    return festivalOfParts(p, lunarParts(p)) || "";
  } catch (e) {
    return "";
  }
}

function todayInfo(date) {
  try {
    const p = partsOf(date);
    if (!p) return { lunar: "", term: "", festival: "", label: "" };
    const lunar = lunarParts(p);
    const lunarLabel = lunar ? lunar.text : "";
    const term = termOfParts(p);
    const fest = festivalOfParts(p, lunar);
    return {
      lunar: lunarLabel,
      term: term,
      festival: fest,
      // 展示优先级：节日 > 节气 > 农历。
      label: fest || term || lunarLabel,
    };
  } catch (e) {
    return { lunar: "", term: "", festival: "", label: "" };
  }
}

module.exports = {
  lunarText: lunarText,
  solarTerm: solarTerm,
  festival: festival,
  todayInfo: todayInfo,
};