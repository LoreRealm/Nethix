pub mod exec;
pub mod plan;

use iced::widget::{button, column, pick_list, text, text_input};
use iced::{Element, Task};

use plan::{FsKind, InstallPlan};

#[derive(Debug, Clone)]
enum Msg {
    Next,
    Back,
    DiskChanged(String),
    FsSelected(FsKind),
    HostnameChanged(String),
    UserChanged(String),
    PasswordChanged(String),
    StartInstall,
}

#[derive(Debug, Clone, PartialEq)]
enum Step {
    Welcome,
    Target,
    Account,
    Ready,
    Running,
}

struct App {
    step: Step,
    plan: InstallPlan,
}

impl App {
    fn new() -> Self {
        App { step: Step::Welcome, plan: InstallPlan::default() }
    }

    fn write_plan(&self) -> Task<Msg> {
        let toml = self.plan.to_toml().unwrap_or_default();
        Task::perform(async move {
            std::fs::create_dir_all("/var/lib/nethix").ok();
            std::fs::write("/var/lib/nethix/cantrip-install-plan.toml", toml).ok();
        }, |_| Msg::Next)
    }
}

impl iced::Program for App {
    type Message = Msg;

    fn update(&mut self, msg: Msg) -> Task<Msg> {
        match msg {
            Msg::Next => {
                self.step = match self.step {
                    Step::Welcome => Step::Target,
                    Step::Target => Step::Account,
                    Step::Account => Step::Ready,
                    _ => self.step.clone(),
                };
            }
            Msg::Back => {
                self.step = match self.step {
                    Step::Target => Step::Welcome,
                    Step::Account => Step::Target,
                    Step::Ready => Step::Account,
                    _ => self.step.clone(),
                };
            }
            Msg::DiskChanged(d) => self.plan.target_disk = d,
            Msg::FsSelected(f) => self.plan.filesystem = f,
            Msg::HostnameChanged(h) => self.plan.hostname = h,
            Msg::UserChanged(u) => self.plan.username = u,
            Msg::PasswordChanged(p) => self.plan.plaintext_password = Some(p),
            Msg::StartInstall => {
                self.step = Step::Running;
                return self.write_plan();
            }
        }
        Task::none()
    }

    fn view(&self) -> Element<'_, Msg> {
        let title = text(format!("Nethix installer — {:?}", self.step)).size(24);
        let body: Element<Msg> = match self.step {
            Step::Welcome => text("Welcome to Nethix (KDE Plasma 6)").into(),
            Step::Target => column![
                text_input("target disk (e.g. /dev/nvme0n1)", &self.plan.target_disk, Msg::DiskChanged),
                pick_list(vec![FsKind::BtrfsZstd, FsKind::Ext4], Some(self.plan.filesystem.clone()), Msg::FsSelected),
            ].spacing(10).into(),
            Step::Account => column![
                text_input("hostname", &self.plan.hostname, Msg::HostnameChanged),
                text_input("username", &self.plan.username, Msg::UserChanged),
                text_input("password", self.plan.plaintext_password.as_deref().unwrap_or(""), Msg::PasswordChanged),
            ].spacing(10).into(),
            Step::Ready => column![
                text(format!("About to install onto {} ({}). This will erase the disk!", self.plan.target_disk, match self.plan.filesystem { FsKind::BtrfsZstd => "btrfs+zstd", FsKind::Ext4 => "ext4" })),
                button("Install").on_press(Msg::StartInstall),
            ].spacing(10).into(),
            Step::Running => text("Installing... (TODO: stream exec output)").into(),
        };
        column![
            title,
            body,
            button("Back").on_press(Msg::Back),
            button("Next").on_press(Msg::Next),
        ].padding(20).spacing(10).into()
    }
}

fn main() -> iced::Result {
    iced::application("Nethix installer", App::update, App::view)
        .run_with(App::new)
}
