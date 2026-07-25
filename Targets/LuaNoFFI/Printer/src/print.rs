use std::io::{Result, Write};

use crate::LuaNoFFIPrinter;

pub trait Print {
	fn print(&self, printer: &mut LuaNoFFIPrinter, out: &mut dyn Write) -> Result<()>;
}

impl<T: Print> Print for &T {
	fn print(&self, printer: &mut LuaNoFFIPrinter, out: &mut dyn Write) -> Result<()> {
		(*self).print(printer, out)
	}
}
