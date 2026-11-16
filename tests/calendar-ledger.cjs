const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const test = require('node:test');
const vm = require('node:vm');
const ts = require(process.env.TYPESCRIPT_PATH || '../ci/node_modules/typescript');

const root = path.resolve(__dirname, '../entry/src/main/ets');
const raw = JSON.parse(fs.readFileSync(path.resolve(root, '../resources/rawfile/metadata/material_meta.json'), 'utf8'));

function createFixture() {
  const fixture = {
    prefs: new Map(),
    storage: new Map(),
    nativeLanguage: 'default',
    projects: [],
    entries: new Map(),
    events: [],
    requestedProjects: [],
    now: Date.parse('2026-11-09T15:50:00Z'),
    timers: new Map(),
    locale: 'zh-Hans',
    systemLocale: 'zh-Hans-CN',
    calendarRequests: [],
  };
  const avatars = [
    { id: 1, quality: 4, name: 'A', icon: 'avatar_a', birth: '11/09', cultivationItems: [0, 0, 0, 0, 104367] },
    { id: 2, quality: 5, name: 'B', icon: 'avatar_b', birth: '11/10', cultivationItems: [0, 0, 0, 0, 104367] },
  ];
  const weapons = [{ id: 3, rankLevel: 5, name: 'Weapon', icon: 'weapon', cultivationItems: [114088] }];
  const materials = new Map([104367, 104370, 114088, 114092, 114096].map(id => [id, raw[id]]));
  const mocks = {
    UiSurface: { UiSurface: { dialogMaterial: () => undefined } },
    PreferencesStore: { PreferencesStore: {
      isReady: () => true,
      getNumber: (key, fallback) => fixture.prefs.get(key) ?? fallback,
      setNumber: (key, value) => fixture.prefs.set(key, value),
      getString: (key, fallback) => fixture.prefs.get(key) ?? fallback,
      setString: (key, value) => fixture.prefs.set(key, value),
    } },
    '@kit.LocalizationKit': { i18n: {
      System: {
        getSystemLocaleInstance: () => ({ toString: () => fixture.systemLocale }),
        getSystemLanguage: () => fixture.systemLocale,
        getAppPreferredLanguage: () => fixture.nativeLanguage,
        setAppPreferredLanguage: language => {
          fixture.nativeLanguage = language;
          if (language !== 'default') fixture.locale = language;
        },
      },
      getCalendar: (locale, calendarType) => {
        fixture.calendarRequests.push([locale, calendarType]);
        return { getFirstDayOfWeek: () => locale === 'en-US' || locale === 'en' ? 1 : 2 };
      },
    } },
    CultivationRepo: { CultivationRepo: {
      getProjects: async () => fixture.projects,
      getEntries: async projectId => {
        fixture.requestedProjects.push(projectId);
        return fixture.entries.get(projectId) ?? [];
      },
    } },
    WikiMetaService: { WikiMetaService: {
      getAvatars: async () => fixture.locale === 'en' ? avatars.map(avatar => ({ ...avatar, name: `${avatar.name} English` })) : avatars,
      getWeapons: async () => weapons,
      getMaterials: async () => fixture.locale === 'en'
        ? new Map(Array.from(materials, ([id, material]) => [id, { ...material, n: `Material ${id}` }])) : materials,
      getGachaEvents: async () => fixture.events,
    } },
    CalendarService: { CalendarService: { getInstance: () => ({ fetchCalendar: async () => [] }) } },
  };
  const modules = new Map();
  let timerId = 0;
  class FixtureDate extends Date {
    static now() { return fixture.now; }
  }
  function load(name) {
    const file = path.resolve(root, name + '.ets');
    if (modules.has(file)) return modules.get(file).exports;
    let source = fs.readFileSync(file, 'utf8').replace(/^@Observed\s*$/gm, '');
    const component = path.basename(file);
    if (component === 'HomeCalendarCard.ets' || component === 'CalendarPage.ets') {
      const endOfLifecycle = component === 'CalendarPage.ets' ? '  @Builder' : '  build() {';
      source = source.slice(0, source.indexOf(endOfLifecycle)) + '\n}';
      source = source.replace(/@\w+(?:\([^)]*\))?\s*/g, '').replace('export struct ', 'export class ');
    }
    const compiled = ts.transpileModule(source, {
      fileName: file.replace(/\.ets$/, '.ts'),
      compilerOptions: { module: ts.ModuleKind.CommonJS, target: ts.ScriptTarget.ES2022 },
      reportDiagnostics: true,
    });
    assert.equal(compiled.diagnostics.length, 0, file);
    const module = { exports: {} };
    modules.set(file, module);
    const loadDependency = id => mocks[id.split('/').at(-1)] ??
      load(path.relative(root, path.resolve(path.dirname(file), id)));
    const run = vm.runInNewContext(`(function(require,module,exports){${compiled.outputText}\n})`, {
      Date: FixtureDate,
      $r: id => ({ id }),
      AppStorage: { get: key => fixture.storage.get(key), setOrCreate: (key, value) => fixture.storage.set(key, value) },
      setInterval: callback => {
        const id = ++timerId;
        fixture.timers.set(id, callback);
        return id;
      },
      clearInterval: id => fixture.timers.delete(id),
    });
    run(loadDependency, module, module.exports);
    return module.exports;
  }
  return {
    fixture,
    service: load('service/CalendarWeekService').CalendarWeekService,
    rules: load('service/GameCalendarRules').GameCalendarRules,
    Ledger: load('model/Ledger').Ledger,
    load,
  };
}

const today = week => week.days.find(day => day.isToday);
const planned = (avatarId, ...ids) => ({ avatarId, items: ids.map(itemId => ({ itemId })) });

test('calendar persists a manual fallback and inherits the selected project timezone for local server dates', async () => {
  const { fixture, service, rules } = createFixture();
  const now = Date.parse('2026-11-08T16:30:00Z');
  const defaultWeek = await service.loadWeek(now);
  assert.equal(defaultWeek.offsetHours, 8);
  assert.equal(today(defaultWeek).monthDay, '11/9');
  assert.equal(defaultWeek.days[0].weekday, 1);
  assert.equal(today(defaultWeek).dateMs, Date.parse('2026-11-08T16:00:00Z'));

  service.setGlobalOffset(-5);
  assert.equal(fixture.prefs.get('app.calendar_server_time_zone_offset'), -5);
  const manualWeek = await service.loadWeek(now);
  assert.equal(manualWeek.offsetHours, -5);
  assert.equal(today(manualWeek).monthDay, '11/8');
  assert.equal(today(manualWeek).allMaterialsOpen, true);
  assert.equal(rules.formatMonthDay(now, -5), '11-08 11:30');

  fixture.projects.push(
    { id: 1, name: '项目一', serverTimeZoneOffset: 8 },
    { id: 2, name: '项目二', serverTimeZoneOffset: 1 },
  );
  fixture.prefs.set('cultivation.current_project_id', 2);
  fixture.prefs.set('calendar.first_day_of_week', 0);
  const selectedWeek = await service.loadWeek(now);
  assert.equal(selectedWeek.globalOffsetHours, -5);
  assert.equal(selectedWeek.offsetHours, 1);
  assert.equal(selectedWeek.projectName, '项目二');
  assert.equal(today(selectedWeek).monthDay, '11/8');
  assert.equal(selectedWeek.days[0].weekday, 0);
  fixture.prefs.set('cultivation.current_project_id', 99);
  assert.equal((await service.loadWeek(now)).offsetHours, 8);
  fixture.projects.length = 0;
  assert.equal((await service.loadWeek(now)).offsetHours, -5);
  service.setGlobalOffset(0.5);
  assert.equal((await service.loadWeek(now)).offsetHours, 8);
});

test('calendar rotates all present families, lists birthdays and highlights only matching project consumers', async () => {
  const { fixture, service, rules } = createFixture();
  fixture.projects.push({ id: 7, name: '培养', serverTimeZoneOffset: 8 }, { id: 9, name: '备用', serverTimeZoneOffset: 8 });
  fixture.entries.set(7, [planned(1, 104365, 104367, 202), planned(3, 114085, 114088)]);
  fixture.entries.set(9, [planned(2, 104366)]);
  fixture.prefs.set('cultivation.current_project_id', 7);
  const now = Date.parse('2026-11-09T04:00:00Z');
  const week = await service.loadWeek(now);
  assert.equal(week.days.length, 7);
  assert.equal(today(week).birthdays[0].name, 'A');
  assert.equal(week.days[1].birthdays[0].name, 'B');
  const talent = today(week).talentMats.find(item => item.id === 104367);
  assert.equal(talent.highlighted, true);
  assert.equal(talent.consumers[0].id, 2, 'higher quality first');
  assert.equal(talent.consumers[0].highlighted, false);
  assert.equal(talent.consumers[1].highlighted, true);
  assert.equal(today(week).weaponMats[0].name, raw[114088].n);
  assert.equal(today(week).weaponMats[0].consumers[0].highlighted, true);
  assert.equal(week.days[1].weaponMats[0].id, 114092);
  assert.equal(week.days[2].weaponMats[0].id, 114096);
  assert.equal(week.days[2].talentMats.length, 0, 'skip unavailable metadata families');
  assert.equal(week.days[2].allMaterialsOpen, false);
  assert.equal(rules.materialDayPair(114085), 1);
  assert.equal(rules.materialDayPair(114089), 2);
  assert.equal(rules.materialDayPair(114093), 3);
  assert.equal(rules.materialDayPair(202), 0);

  fixture.prefs.set('cultivation.current_project_id', 9);
  const afterSwitch = today(await service.loadWeek(now));
  assert.equal(afterSwitch.talentMats[0].consumers[0].highlighted, true);
  assert.equal(afterSwitch.talentMats[0].consumers[1].highlighted, false);
  assert.equal(afterSwitch.weaponMats[0].highlighted, false);
  assert.equal(talent.consumers[0].highlighted, false, 'existing snapshot remains independent');
  assert.deepEqual(fixture.requestedProjects, [7, 9]);
});

test('calendar uses the locale week start until an explicit Sunday is saved', async () => {
  const { fixture, service, load } = createFixture();
  const locale = load('service/AppLocaleService').AppLocaleService;
  const now = Date.parse('2026-11-08T16:30:00Z');
  fixture.systemLocale = 'en-GB';
  locale.initialize();
  assert.equal(locale.requested(), 'en-GB');
  const britishWeek = await service.loadWeek(now);
  assert.equal(britishWeek.days[0].weekday, 1);
  fixture.systemLocale = 'en-US';
  assert.equal(locale.onConfigurationUpdate('en'), true);
  assert.equal(locale.requested(), 'en-US');
  assert.equal(locale.current(), 'en');
  const americanWeek = await service.loadWeek(now);
  assert.equal(americanWeek.days[0].weekday, 0);
  assert.equal(today(britishWeek).dateMs, today(americanWeek).dateMs);
  assert.equal(today(americanWeek).monthDay, '11/9');
  assert.equal(fixture.prefs.has('calendar.first_day_of_week'), false);

  assert.equal(locale.select('fr'), true);
  assert.equal(service.firstDayOfWeek(), 1);
  assert.equal(locale.select('en'), true);
  assert.equal(service.firstDayOfWeek(), 0);
  assert.deepEqual(fixture.calendarRequests, [['en-GB', 'gregory'], ['en-US', 'gregory'], ['fr', 'gregory'], ['en', 'gregory']]);
  fixture.systemLocale = 'en-GB';
  assert.equal(locale.select('system'), true);
  assert.equal(locale.restartRequired(), true);
  assert.equal(service.firstDayOfWeek(), 0, 'pending native reset keeps the current English calendar until cold start');
  service.setFirstDayOfWeek(0);
  assert.equal(fixture.prefs.get('calendar.first_day_of_week'), 0);
  assert.equal(locale.select('fr'), true);
  assert.equal((await service.loadWeek(now)).days[0].weekday, 0);
  assert.equal(fixture.calendarRequests.length, 5, 'saved Sunday does not consult the locale default');
  service.setFirstDayOfWeek(7);
  assert.equal(service.firstDayOfWeek(), 0);
});

test('character banners open all material domains for seven inclusive calendar dates in the effective timezone', async () => {
  const { fixture, service } = createFixture();
  service.setGlobalOffset(-5);
  const start = Date.parse('2026-10-01T00:10:00+08:00');
  fixture.events = [{ from: start, type: 302 }];
  assert.equal(today(await service.loadWeek(Date.parse('2026-09-30T06:00:00Z'))).allMaterialsOpen, false);
  fixture.events = [{ from: start, type: 400 }];
  assert.equal(today(await service.loadWeek(Date.parse('2026-09-29T23:59:59-05:00'))).allMaterialsOpen, false);
  const firstDay = today(await service.loadWeek(Date.parse('2026-09-30T00:00:00-05:00')));
  assert.equal(firstDay.monthDay, '9/30');
  assert.equal(firstDay.allMaterialsOpen, true);
  assert.equal(firstDay.weaponMats.length, 0);
  assert.equal(today(await service.loadWeek(Date.parse('2026-10-06T23:59:59-05:00'))).allMaterialsOpen, true);
  assert.equal(today(await service.loadWeek(Date.parse('2026-10-07T00:00:00-05:00'))).allMaterialsOpen, false);
});

test('home calendar follows the server-day rollover, preserves selected dates and marks full event dates', async () => {
  const { fixture, load } = createFixture();
  const { HomeCalendarCard } = load('components/HomeCalendarCard');
  const card = new HomeCalendarCard();
  const flush = () => new Promise(resolve => setImmediate(resolve));
  card.aboutToAppear();
  await flush();
  assert.equal(card.selectedDay().monthDay, '11/9');
  assert.equal(card.selectedMaterials()[0].id, 104367);
  card.eventDays = [Date.parse('2026-12-09T15:59:00Z')];
  assert.equal(card.hasEvent(card.selectedDay()), false);
  card.eventDays.push(Date.parse('2026-11-09T15:59:00Z'));
  assert.equal(card.hasEvent(card.selectedDay()), true);

  fixture.now = Date.parse('2026-11-09T16:01:00Z');
  for (const callback of fixture.timers.values()) callback();
  await flush();
  assert.equal(card.selectedDay().monthDay, '11/10');
  assert.equal(card.selectedMaterials()[0].id, 104370);
  card.selectedDateMs = card.week.days[0].dateMs;
  await card.loadWeek();
  assert.equal(card.selectedDay().monthDay, '11/9');
  assert.equal(card.selectedDay().birthdays[0].name, 'A');
  card.aboutToDisappear();
  assert.equal(fixture.timers.size, 0);
});

test('visible calendars reload localized names on a language change and keep the selected server date', async () => {
  const { fixture, load } = createFixture();
  const pagePath = 'pages/CalendarPage';
  const cardPath = 'components/HomeCalendarCard';
  const page = new (load(pagePath).CalendarPage)();
  const card = new (load(cardPath).HomeCalendarCard)();
  const flush = () => new Promise(resolve => setImmediate(resolve));
  const notifyLocaleChange = (pathName, view) => {
    const source = fs.readFileSync(path.resolve(root, pathName + '.ets'), 'utf8');
    const handler = source.match(/@StorageProp\('helpLocaleVersion'\)\s+@Watch\('([^']+)'\)/)?.[1];
    assert.ok(handler, pathName + ' must observe the app language version');
    return view[handler]();
  };
  page.aboutToAppear();
  card.aboutToAppear();
  await flush();
  const selectedDate = card.week.days[1].dateMs;
  card.selectedDateMs = selectedDate;
  page.vm.selectedDateMs = selectedDate;
  assert.equal(card.selectedDay().birthdays[0].name, 'B');
  assert.equal(page.vm.selectedDay().talentMats[0].name, raw[104370].n);

  assert.equal(load('service/AppLocaleService').AppLocaleService.select('en'), true);
  notifyLocaleChange(pagePath, page);
  await notifyLocaleChange(cardPath, card);
  await flush();
  for (const view of [page.vm, card]) {
    assert.equal(view.selectedDateMs, selectedDate);
    assert.equal(view.selectedDay().birthdays[0].name, 'B English');
    assert.equal(view.selectedDay().talentMats[0].name, 'Material 104370');
  }

  page.aboutToDisappear();
  card.aboutToDisappear();
  assert.equal(load('service/AppLocaleService').AppLocaleService.select('zh-Hans'), true);
  notifyLocaleChange(pagePath, page);
  await notifyLocaleChange(cardPath, card);
  await flush();
  assert.equal(page.vm.selectedDay().birthdays[0].name, 'B English');
  assert.equal(card.selectedDay().birthdays[0].name, 'B English');
  assert.equal(card.week.days[0].weekday, 0);
});

test('home material popup uses the picked day and opens exact character and weapon Wiki routes', async () => {
  const { fixture, service, load } = createFixture();
  fixture.projects = [{ id: 7, serverTimeZoneOffset: 8 }];
  fixture.entries.set(7, [planned(2, 104367)]);
  let weeksRead = 0;
  const loadWeek = service.loadWeek.bind(service);
  service.loadWeek = (...args) => { weeksRead++; return loadWeek(...args); };
  const card = new (load('components/HomeCalendarCard').HomeCalendarCard)();
  const routes = [];
  card.getUIContext = () => ({ getRouter: () => ({ pushUrl: async route => routes.push(route) }) });
  card.aboutToAppear(); await new Promise(resolve => setImmediate(resolve));
  const thursday = card.week.days.find(day => day.weekday === 4);
  card.selectDate(thursday.dateMs);
  const talent = thursday.talentMats.find(material => material.id === 104367);
  const weapon = thursday.weaponMats.find(material => material.id === 114088);
  card.openMaterial(talent.id);
  assert.equal(card.popupMaterial, talent);
  assert.deepEqual(Array.from(card.popupMaterial.consumers, item => [item.id, item.highlighted]), [[2, true], [1, false]]);
  await card.openConsumer(talent.id, weapon.consumers[0]);
  assert.equal(routes.length, 0, 'a consumer must belong to the open material');
  await card.openConsumer(talent.id, talent.consumers[0]);
  await card.openConsumer(talent.id, talent.consumers[0]);
  assert.equal(card.popupMaterial, undefined);
  card.openMaterial(talent.id); card.openMaterial(weapon.id);
  card.dismissMaterial(talent.id);
  assert.equal(card.popupMaterial, weapon, 'late dismissal of a different anchor leaves the current popup open');
  await card.openConsumer(weapon.id, weapon.consumers[0]);
  assert.deepEqual(JSON.parse(JSON.stringify(routes)), [
    { url: 'pages/WikiAvatarPage', params: { itemId: 2 } },
    { url: 'pages/WikiWeaponPage', params: { itemId: 3 } },
  ]);
  assert.equal(card.selectedDateMs, thursday.dateMs);
  assert.equal(weeksRead, 1, 'opening and navigating reuse the already loaded week');
  card.aboutToDisappear();
});

test('home material selection follows refreshed data and clears when its day or card changes', async () => {
  const { load } = createFixture();
  const card = new (load('components/HomeCalendarCard').HomeCalendarCard)();
  card.aboutToAppear(); await new Promise(resolve => setImmediate(resolve));
  const material = card.selectedMaterials().find(item => item.id === 104367);
  card.openMaterial(material.id);
  assert.equal(load('service/AppLocaleService').AppLocaleService.select('en'), true);
  await card.loadWeek();
  assert.equal(card.popupMaterial.name, 'Material 104367');
  assert.equal(card.popupMaterial.consumers[0].name, 'B English');
  card.selectDate(card.week.days.find(day => day.weekday === 0).dateMs);
  assert.equal(card.popupMaterial, undefined);
  card.openMaterial(material.id);
  assert.equal(card.popupMaterial, undefined, 'Sunday has no rotation button');
  card.selectDate(card.week.days.find(day => day.weekday === 1).dateMs);
  card.openMaterial(material.id);
  card.aboutToDisappear();
  await card.openConsumer(material.id, material.consumers[0]);
  assert.equal(card.popupMaterial, undefined);
});

test('calendar weekday text uses the shared Settings resources in server date order', async () => {
  const { service, load } = createFixture();
  const { calendarDateLabel, calendarWeekdayLabel } = load('components/CalendarWeekdayLabel');
  const week = await service.loadWeek(Date.parse('2026-11-08T16:30:00Z'));
  const english = JSON.parse(fs.readFileSync(path.resolve(root, '../resources/en/element/ui_labels.json'), 'utf8'));
  const strings = new Map(english.string.map(({ name, value }) => ['app.string.' + name, value]));
  const context = { getHostContext: () => ({ resourceManager: { getStringSync: id => strings.get(id) } }) };
  assert.deepEqual(Array.from(week.days, day => strings.get(calendarWeekdayLabel(day.weekday).id)),
    ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun']);
  assert.equal(calendarDateLabel(context, today(week)), 'Mon 11/9 · Today');
  assert.equal(calendarDateLabel(context, week.days[6]), 'Sun 11/15');
});

test('ledger keeps real zeroes, missing day data and valid income sources distinguishable', () => {
  const { Ledger } = createFixture();
  const ledger = Ledger.fromJson({
    month: 11,
    optional_month: [11, '11', '10', 0, 13, false],
    month_data: {
      current_primogems: 50, primogems_rate: 0, mora_rate: '',
      group_by: [null, { action: 'zero', num: 0, percent: 0 }, { action: 'source', num: 50, percent: 100 }],
    },
  });
  assert.equal(ledger.dayData, undefined);
  assert.deepEqual(Array.from(ledger.optionalMonth), [11, 10]);
  assert.equal(ledger.monthData.primogemsRate, 0);
  assert.equal(ledger.monthData.moraRate, undefined);
  assert.equal(ledger.monthData.groupBy.length, 1);
  assert.equal(ledger.monthData.groupBy[0].action, 'source');
  assert.equal(Ledger.fromJson({ day_data: { current_primogems: 0, current_mora: 0 } }).dayData.currentMora, 0);
});
