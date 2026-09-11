// The languages a GPU host will accept a shader in.
package gpu

import cortado.host

/// A shading language.
///
/// **This is the one place cortado does not hide a difference between
/// platforms, and that is deliberate.** Everywhere else in this library the
/// point is that the same program runs everywhere: a `Button` is an NSButton
/// here and a GtkButton there and the program never knows. A shader cannot
/// work that way. MSL, HLSL and SPIR-V are three languages with three
/// compilers, and the only way to paper over that is to vendor a translator —
/// a project larger than this one, whose output would still not be exact.
///
/// So cortado says which language the host in front of you speaks, and a
/// program that wants to run on Metal and Direct3D ships two shaders and picks
/// one. That is more work than pretending, and it is work that actually
/// finishes.
pub enum(u8) ShaderLanguage {
    msl
    hlsl
    spirv
    glsl

    pub fn name() -> string {
        return match self {
            msl => "msl",
            hlsl => "hlsl",
            spirv => "spirv",
            glsl => "glsl",
        }
    }

    /// The bit this language has in the host's answer.
    ///
    /// A bit rather than a number because a host may accept more than one, and
    /// a single number could not say so.
    pub fn bit() -> int {
        return match self {
            msl => host.SHADER_MSL,
            hlsl => host.SHADER_HLSL,
            spirv => host.SHADER_SPIRV,
            glsl => host.SHADER_GLSL,
        }
    }

    /// Every language, in the order they are declared, so a caller can ask
    /// about each without naming them again.
    pub static fn all() -> List<ShaderLanguage> {
        var every: List<ShaderLanguage> = []
        every.push(ShaderLanguage.msl)
        every.push(ShaderLanguage.hlsl)
        every.push(ShaderLanguage.spirv)
        every.push(ShaderLanguage.glsl)
        return move every
    }

    /// Whether the host running this program will compile a shader written in
    /// it. A host with no GPU at all accepts none, and says so by accepting
    /// none rather than by naming a language it could never run.
    pub fn accepted() -> bool {
        return (ShaderLanguage.offered() & self.bit()) != 0
    }

    /// The raw answer: every bit the host set.
    ///
    /// Exposed because the bits and the names can disagree in one direction
    /// this enum cannot express. A host built against a newer header may offer
    /// a language whose name is not in this list, and a program told only
    /// "none of the four" would read that as "no shaders" — which is the
    /// silent wrong answer cortado exists to avoid. `unnamed` is how a caller,
    /// or a test, sees it.
    pub static fn offered() -> int {
        unsafe {
            return host.ctd_gpu_shader_langs() as int
        }
    }

    /// The bits the host set that no name here accounts for. Zero on a host
    /// this build understands.
    pub static fn unnamed() -> int {
        var named: int = 0
        let every: List<ShaderLanguage> = ShaderLanguage.all()
        for language: ShaderLanguage in every {
            named = named | language.bit()
        }
        return ShaderLanguage.offered() & ~named
    }
}
