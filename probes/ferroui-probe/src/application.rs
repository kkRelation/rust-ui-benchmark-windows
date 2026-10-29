use std::cell::{Cell, RefCell};
use std::rc::Rc;

use ferroui::base::reactive::IDisposable;
use ferroui::base::Size;
use ferroui::prelude::*;

use crate::controller::{self, readiness_complete, UiRequest};
use crate::scene::{AuxiliaryScene, MainScene};

const MAIN_TITLE: &str = "UI Framework Bench - Main";
const AUXILIARY_TITLE: &str = "UI Framework Bench - Auxiliary Canvas";
const MAIN_SIZE: Size = Size::new(700.0, 480.0);
const AUXILIARY_SIZE: Size = Size::new(1200.0, 760.0);

thread_local! {
    static RUNTIME: RefCell<Option<BenchRuntime>> = const { RefCell::new(None) };
}

pub struct BenchRuntime {
    main_window: Ref<Window>,
    auxiliary_window: Ref<Window>,
    main_scene: MainScene,
    auxiliary_scene: AuxiliaryScene,
    selected: usize,
    allow_close: Rc<Cell<bool>>,
    _closing_subscriptions: Vec<Rc<dyn IDisposable>>,
}

impl BenchRuntime {
    fn new() -> Self {
        let main_scene = MainScene::new();
        let auxiliary_scene = AuxiliaryScene::new();

        let main_window = Window::new();
        main_window.set_title(Some(MAIN_TITLE.to_string()));
        main_window.set_client_size(MAIN_SIZE);
        main_window.set_content(Some(Control::boxed(main_scene.root())));

        let auxiliary_window = Window::new();
        auxiliary_window.set_title(Some(AUXILIARY_TITLE.to_string()));
        auxiliary_window.set_client_size(AUXILIARY_SIZE);
        auxiliary_window.set_content(Some(Control::boxed(auxiliary_scene.root())));

        let allow_close = Rc::new(Cell::new(false));
        let subscriptions = [&main_window, &auxiliary_window]
            .into_iter()
            .map(|window| {
                let allow_close = allow_close.clone();
                window.closing(move |event| {
                    if !allow_close.get() {
                        event.set_cancel(true);
                    }
                })
            })
            .collect();

        Self {
            main_window,
            auxiliary_window,
            main_scene,
            auxiliary_scene,
            selected: 0,
            allow_close,
            _closing_subscriptions: subscriptions,
        }
    }

    fn initialize_hidden(&self) -> Result<(), String> {
        self.main_window.show();
        self.auxiliary_window.show();
        self.main_window.set_client_size(MAIN_SIZE);
        self.auxiliary_window.set_client_size(AUXILIARY_SIZE);
        self.main_window.hide();
        self.auxiliary_window.hide();

        let created = self.main_window.platform_impl().is_some()
            && self.auxiliary_window.platform_impl().is_some();
        let sized = self.main_window.client_size() == MAIN_SIZE
            && self.auxiliary_window.client_size() == AUXILIARY_SIZE;
        let hidden = !self.main_window.is_visible() && !self.auxiliary_window.is_visible();

        if readiness_complete(created, sized, hidden) {
            Ok(())
        } else {
            Err(format!(
                "FerroUI readiness failed: created={created} sized={sized} hidden={hidden}"
            ))
        }
    }

    fn set_visible(&self, visible: bool) {
        if visible {
            self.main_window.show();
            self.auxiliary_window.show();
        } else {
            self.main_window.hide();
            self.auxiliary_window.hide();
        }
    }

    fn set_selected(&mut self, selected: usize) {
        let previous = self.selected;
        self.selected = selected;
        self.main_scene.set_selected(previous, selected);
        self.auxiliary_scene.set_selected(previous, selected);
    }

    fn quit(&self) {
        self.allow_close.set(true);
        self.auxiliary_window.close();
        self.main_window.close();
    }

    fn apply(&mut self, request: UiRequest) -> Result<(), String> {
        match request {
            UiRequest::InitializeHidden => self.initialize_hidden(),
            UiRequest::SetVisible(visible) => {
                self.set_visible(visible);
                Ok(())
            }
            UiRequest::SetSelection(selected) => {
                self.set_selected(selected);
                Ok(())
            }
            UiRequest::Barrier => Ok(()),
            UiRequest::Quit => {
                self.quit();
                Ok(())
            }
        }
    }
}

pub fn apply_request(request: UiRequest) -> Result<(), String> {
    RUNTIME.with(|runtime| {
        runtime
            .borrow_mut()
            .as_mut()
            .ok_or_else(|| "FerroUI runtime is not initialized".to_string())?
            .apply(request)
    })
}

#[repr(C)]
pub struct BenchApplication {
    base: Application,
}

ferro_class!(BenchApplication: Application);
ferro_impl_classes!(BenchApplication: FerroObjectImpl);

impl NewApplication for BenchApplication {
    fn new_application() -> Ref<Self> {
        instantiate(Self {
            base: Application::construct(),
        })
    }
}

impl ApplicationImpl for BenchApplication {
    fn initialize(this: &Self) {
        Self::parent_initialize(this);
        this.styles().add(FluentTheme::new().as_style());
    }

    fn on_framework_initialization_completed(this: &Self) {
        let lifetime = this.application_lifetime();
        if let Some(desktop) = lifetime
            .as_ref()
            .and_then(|lifetime| lifetime.as_classic_desktop_style_application_lifetime())
        {
            let runtime = BenchRuntime::new();
            desktop.set_main_window(Some(runtime.main_window.clone()));
            RUNTIME.with(|slot| *slot.borrow_mut() = Some(runtime));
            controller::start_controller();
        }
        Self::parent_on_framework_initialization_completed(this);
    }
}
