/// What `tyler` reads from a `Tyler.app`'s `Info.plist`.
package struct AppInfo: Equatable, Sendable {
  /// `CFBundleVersion`: a stamp `devtools/make-app` gives each build.
  package var build: String?
  /// Whether it is a release, which runs from its copy in `~/Applications`
  /// (`TylerInstallsInApplications`), rather than where it was built.
  package var installsInApplications: Bool
  package var bundleID: String?
  /// Whether it is signed ad hoc (`TylerSignedAdHoc`): every build is then another identity to
  /// macOS, which asks for the grant again.
  package var isSignedAdHoc: Bool

  package init(
    build: String?, installsInApplications: Bool, bundleID: String? = nil,
    isSignedAdHoc: Bool = false
  ) {
    self.build = build
    self.installsInApplications = installsInApplications
    self.bundleID = bundleID
    self.isSignedAdHoc = isSignedAdHoc
  }
}
