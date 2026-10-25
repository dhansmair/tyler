/// What `tyler` reads from a `Tyler.app`'s `Info.plist`.
package struct AppInfo: Equatable, Sendable {
  /// `CFBundleVersion`: a stamp `devtools/make-app` gives each build.
  package var build: String?
  /// Whether it is a release, which runs from its copy in `~/Applications`
  /// (`TylerInstallsInApplications`), rather than where it was built.
  package var installsInApplications: Bool

  package init(build: String?, installsInApplications: Bool) {
    self.build = build
    self.installsInApplications = installsInApplications
  }
}
