use ferroui::prelude::*;

#[repr(C)]
struct BenchApplication {
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
            let window = Window::new();
            window.set_title(Some("UI Framework Bench - Main".to_string()));
            desktop.set_main_window(Some(window));
        }
        Self::parent_on_framework_initialization_completed(this);
    }
}

fn main() -> std::process::ExitCode {
    let arguments: Vec<String> = std::env::args().skip(1).collect();
    let exit_code = AppBuilder::configure::<BenchApplication>()
        .use_platform_detect()
        .start_with_classic_desktop_lifetime(&arguments);
    std::process::ExitCode::from(exit_code as u8)
}
