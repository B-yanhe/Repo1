// dsh-brand-title — browser half of the client bundle.
//
// dsh-client-ui-layout's DocumentTitle component writes
//   document.title = "<session title> — DeepSeek Harness"
// whenever the selected session changes, so the app window's title bar shows
// the conversation name. This plugin pins the browser title to the product
// name instead.
//
// Two layers, because a single one is not enough:
//   1. an own `document.title` accessor on the document instance — the app's
//      writes become no-ops, so nothing flickers;
//   2. a MutationObserver on <head> — catches anything that edits the <title>
//      element directly rather than through document.title.
//
// The window title bar is derived from the <title> element, so the element
// itself is what has to stay pinned.
//
// The host does not isolate loader-entry factories, so the factory body must
// never throw: on any failure it returns a no-op plugin instead.

window.__ModuleLoader__.load({
	id: 'dsh-brand-title',
	factory: () => {
		const PRODUCT_TITLE = 'DeepSeek Harness';

		/** Force the real <title> element back to the product name. */
		function pinTitleElement() {
			const head = document.head;
			if (head === null || head === undefined) return;
			let element = document.querySelector('title');
			if (element === null) {
				element = document.createElement('title');
				head.appendChild(element);
			}
			if (element.textContent !== PRODUCT_TITLE) element.textContent = PRODUCT_TITLE;
		}

		/** Cordis plugin that owns both the accessor override and the observer. */
		function apply(ctx) {
			ctx.effect(() => {
				pinTitleElement();

				const hadOwnTitle = Object.prototype.hasOwnProperty.call(document, 'title');
				const previous = Object.getOwnPropertyDescriptor(document, 'title');
				Object.defineProperty(document, 'title', {
					configurable: true,
					enumerable: previous === undefined ? false : previous.enumerable,
					get() {
						return PRODUCT_TITLE;
					},
					set() {
						pinTitleElement();
					},
				});

				const observer = new MutationObserver(pinTitleElement);
				if (document.head !== null && document.head !== undefined) {
					observer.observe(document.head, {
						childList: true,
						subtree: true,
						characterData: true,
					});
				}

				return () => {
					observer.disconnect();
					if (hadOwnTitle && previous !== undefined) Object.defineProperty(document, 'title', previous);
					else delete document.title;
				};
			}, 'brand-title: pin the browser title');
		}

		try {
			pinTitleElement();
			return { name: 'dsh-brand-title', apply };
		} catch (error) {
			console.warn('[dsh-brand-title] disabled:', error);
			return { name: 'dsh-brand-title', apply() {} };
		}
	},
});
