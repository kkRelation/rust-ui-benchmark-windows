use makepad_widgets::*;

use crate::controller::start_controller;

live_design! {
    use link::theme::*;
    use link::shaders::*;
    use link::widgets::*;
    use crate::scene::*;

    App = {{App}} {
        ui: <MultiWindow> {
            main_window = <Window> {
                window: {
                    title: "UI Framework Bench - Main",
                    inner_size: vec2(700, 480)
                }
                body = <MainScene> {}
            }
            auxiliary_window = <Window> {
                window: {
                    title: "UI Framework Bench - Auxiliary Canvas",
                    inner_size: vec2(1200, 760)
                }
                body = <AuxiliaryScene> {}
            }
        }
    }
}

app_main!(App);

#[derive(Live, LiveHook)]
pub struct App {
    #[live]
    ui: WidgetRef,
    #[rust]
    selected: usize,
}

impl App {
    pub fn set_selected(&mut self, cx: &mut Cx, selected: usize) {
        self.selected = selected;
        self.ui.redraw(cx);
    }
}

impl LiveRegister for App {
    fn live_register(cx: &mut Cx) {
        makepad_widgets::live_design(cx);
        crate::scene::live_design(cx);
    }
}

impl MatchEvent for App {
    fn handle_startup(&mut self, _cx: &mut Cx) {
        start_controller(self.ui_runner());
    }
}

impl AppMain for App {
    fn handle_event(&mut self, cx: &mut Cx, event: &Event) {
        let runner = self.ui_runner();
        runner.handle(cx, event, &mut Scope::empty(), self);
        self.match_event(cx, event);

        // One top-level Rust value is projected into both retained windows.
        let selected = self.selected;
        self.ui
            .handle_event(cx, event, &mut Scope::with_props(&selected));
    }
}
