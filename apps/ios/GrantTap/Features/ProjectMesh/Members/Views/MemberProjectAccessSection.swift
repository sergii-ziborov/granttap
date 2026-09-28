import SwiftUI

struct MemberProjectAccessSection: View {
    let link: MemberLink
    @ObservedObject var model: AppModel
    @State private var saveError = false

    private var projects: [ProjectMeshSnapshot] {
        model.meshSnapshots.values.filter {
            link.allowsProject($0.projectId) || !model.ownComputerRooms(for: $0.projectId).isEmpty
        }.sorted { $0.project.name < $1.project.name }
    }

    var body: some View {
        Section {
            ForEach(projects) { project in
                Toggle(isOn: Binding(
                    get: { link.allowsProject(project.projectId) },
                    set: { enabled in
                        var updated = link
                        var ids = link.projectIds
                        if enabled { ids.insert(project.projectId) }
                        else if project.projectId != link.projectId { ids.remove(project.projectId) }
                        updated.sharedProjectIds = ids.sorted()
                        saveError = !model.updateMemberLink(updated)
                    }
                )) {
                    VStack(alignment: .leading, spacing: 3) {
                        Text(project.project.name)
                        Text(project.project.canonicalRepositoryId)
                            .font(.caption2).foregroundStyle(Theme.muted)
                        if link.allowsProject(project.projectId)
                            && !model.memberCanAccessProject(link, projectId: project.projectId) {
                            Text(L("Blocked by company repository grant"))
                                .font(.caption2).foregroundStyle(Theme.riskHigh)
                        }
                    }
                }
                .disabled(project.projectId == link.projectId
                          || (!link.allowsProject(project.projectId)
                              && (model.ownComputerRooms(for: project.projectId).isEmpty
                                  || link.companyAccountId.flatMap { id in
                                      model.companyAccounts.first(where: { $0.id == id })
                                  }.map { !CompanyAccountPolicy.canReceive(project, account: $0) } ?? false)))
                .accessibilityIdentifier("member.project.\(project.projectId)")
            }
        } header: {
            Text(L("Mesh spaces and repositories"))
        } footer: {
            Text(saveError
                 ? L("Access change was not saved securely.")
                 : L("This device receives only selected Mesh spaces when its company account also covers every repository in each Mesh. Removing access stops new forwarding; already delivered data remains on the device."))
        }
    }
}
