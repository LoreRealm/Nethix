//! Nethix GUI installer skeleton: staged install into a chroot.
//! Steps: welcome -> disk target -> microarch profile -> install
use iced::widget::{button, column, text};
use iced::{Element, Task};

#[derive(Debug, Clone)]
enum Step {
    Welcome,
    Target,
    Microarch,
    Installing,
}

#[derive(Debug, Clone)]
enum Msg {
    Next,
    Back,
}

struct App {
    step: Step,
    cpu_flags: Vec<String>,
    target_disk: Option<String>,
}

impl App {
    fn new() -> Self {
        App {
            step: Step::Welcome,
            cpu_flags: detect_cpu_flags(),
            target_disk: None,
        }
    }
}

/// Parse /proc/cpuinfo flags to recommend x86-64-v2/v3/v4 profile.
fn detect_cpu_flags() -> Vec<String> {
    std::fs::read_to_string("/proc/cpuinfo")
        .ok()
        .and_then(|s| {
            s.lines()
                .find(|l| l.starts_with("flags"))
                .map(|l| l.split(':').nth(1).unwrap_or("").split_whitespace().map(String::from).collect())
        })
        .unwrap_or_default()
}

impl iced::Program for App {
    type Message = Msg;

    fn update(&mut self, _msg: Msg) -> Task<Msg> {
        Task::none()
    }

    fn view(&self) -> Element<'_, Msg> {
        let body = match self.step {
            Step::Welcome => text("Nethix installer — KDE Plasma 6").into(),
            Step::Target => text(format!("target disk: {:?}", self.target_disk)).into(),
            _ => text("TODO").into(),
        };
        column![body, button("Next").on_press(Msg::Next)].padding(20).into()
    }
}

fn main() -> iced::Result {
    iced::application("Nethix installer", App::update, App::view)
        .run_with(App::new)
}
