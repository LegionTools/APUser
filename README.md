# APUser (Artifact Power User)

A minimal Legion 7.3.5 addon for using "Artifact Power" consumables straight from your bags, without opening them.

## Features

- **Minimap button** (draggable, like any other minimap addon button).
- **Hover tooltip**: how many Artifact Power items you're carrying and their combined power (formatted as тыс/млн/млрд to match the game's own number style).
- **Click**, or **Alt + MouseWheel** (up or down), to use one — always targets the first Artifact Power item found in your bags.
- Skips using an item while you're casting or channeling, so it never clips a cast. A brief delay after each use also guards against a second click/scroll landing before the server has confirmed the cast actually started.

## Installation

Drop the `APUser` folder into `Interface/AddOns/`.

## Commands

- `/apdebug` — lists every item currently detected as Artifact Power (link, computed amount, raw tooltip lines). Useful if a future patch changes the tooltip wording and detection stops working — the detection is text-based (keyword + "млн"/"млрд"/"тыс" magnitude words), not a stable item-flag lookup, since Blizzard doesn't expose one.

## Known limitations

- No custom minimap icon yet (plain scroll icon placeholder).
- Russian and English tooltip keywords are recognized; other locales aren't.

---

# APUser (Artifact Power User)

Минимальный аддон для Legion 7.3.5 — использование предметов «Сила артефакта» прямо из сумок, без открытия каждого по отдельности.

## Возможности

- **Кнопка на миникарте** (перетаскивается, как у любого другого аддона).
- **Тултип при наведении**: сколько предметов Силы артефакта в сумках и их суммарная сила (в формате тыс/млн/млрд, как в самой игре).
- **Клик** или **Alt + колесо мыши** (вверх или вниз) — использовать один предмет: всегда берётся первый найденный в сумках предмет Силы артефакта.
- Не использует предмет во время каста/ченнелинга, чтобы не сорвать заклинание. Небольшая задержка после каждого использования также защищает от повторного клика/скролла до того, как сервер подтвердит реальный старт каста.

## Установка

Положите папку `APUser` в `Interface/AddOns/`.

## Команды

- `/apdebug` — выводит список всех предметов, которые аддон определил как Силу артефакта (ссылка, посчитанное значение, сырые строки тултипа). Пригодится, если очередной патч поменяет формулировки в тултипе и распознавание перестанет работать — определение идёт по тексту (ключевое слово + слова-множители «млн»/«млрд»/«тыс»), а не по стабильному флагу предмета, которого Blizzard для этого не даёт.

## Известные ограничения

- Своей иконки на миникарте пока нет (временная заглушка — иконка свитка).
- Распознаются русские и английские ключевые слова в тултипе, остальные локали — нет.
