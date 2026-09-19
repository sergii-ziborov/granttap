import SwiftUI
import WebKit

struct ProjectMeshStatusView: View {
    let snapshot: ProjectMeshSnapshot
    @ObservedObject var model: AppModel
    @State private var toast: String?

    var bindings: [ProjectBindingSummary] {
        ProjectMeshLogic.visibleBindings(snapshot.bindings ?? []).sorted {
            $0.displayName == $1.displayName
                ? $0.bindingId < $1.bindingId : $0.displayName < $1.displayName
        }
    }

    var peers: [ProjectIntegrationPeer] {
        (snapshot.peers ?? []).sorted { $0.id < $1.id }
    }

    var repoLens: ProjectRepoLensPresentation.Graph {
        ProjectRepoLensPresentation.graph(snapshot)
    }

    var body: some View {
        List {
            Section {
                ProjectRepoLensGraphView(graph: repoLens)
            } footer: {
                Text(repoLens.rowDetail)
            }
            Section(L("Mesh")) {
                CompatLabeledContent(
                    L("Mode"), value: ProjectManagePresentation.meshSummary(snapshot)
                )
                CompatLabeledContent(L("Tasks"), value: "\(snapshot.tasks.count)")
                CompatLabeledContent(L("Executions"), value: "\(snapshot.executions.count)")
                if snapshot.incomplete == true {
                    Text(L("Bounded snapshot. Not the whole Project."))
                        .font(.caption).foregroundStyle(Theme.muted)
                }
            }
            projectUsageSection
            Section(L("Repository bindings")) {
                if bindings.isEmpty {
                    Text(L("No repository bindings reported."))
                        .foregroundColor(Theme.muted)
                } else {
                    ForEach(bindings) { binding in ProjectBindingRow(binding: binding, model: model) }
                }
            }
            Section {
                if peers.isEmpty {
                    Text(L("No integration edges reported yet."))
                        .font(.caption).foregroundStyle(Theme.muted)
                } else {
                    ForEach(peers) { peer in ProjectIntegrationPeerRow(peer: peer, snapshot: snapshot) }
                }
            } header: {
                Text(L("Integration map"))
            } footer: {
                Text(L("From WEAVATRIX.md in each bound repository. Only stated edges are shown."))
            }
        }
        .navigationTitle(L("Health / Graph"))
        .transientToast($toast)
    }

    /// A Project is the only scope that spans machines, so it is the only one
    /// that can answer which machine is carrying it — and every number here
    /// opens: a computer to what it did, a tool to its calls, a call to the
    /// chat at the moment it happened.
    @ViewBuilder private var projectUsageSection: some View {
        let sessionIds = ProjectUsageStats.sessionIds(snapshot)
        let events = ProjectUsageStats.events(
            CapabilityUsageStore.shared.events, snapshot: snapshot
        )
        inventorySection(events: events)
        if !events.isEmpty {
            if let totals = TaskUsageHistory.totals(events, sessionIds: sessionIds) {
                Section(L("This Project")) {
                    CompatLabeledContent(L("Calls"), value: "\(totals.calls)")
                    if totals.failures > 0 {
                        CompatLabeledContent(L("Failed"), value: "\(totals.failures)")
                    }
                    if let cpu = totals.cpuTimeMs {
                        CompatLabeledContent(L("CPU time"), value: CapabilityResourceFormat.duration(cpu))
                    }
                    if let peak = totals.peakMemoryBytes {
                        CompatLabeledContent(L("Peak memory"), value: CapabilityResourceFormat.bytes(peak))
                    }
                    CompatLabeledContent(
                        L("Tokens"), value: Format.tokens(ProjectUsageStats.tokens(
                            model.sessions + model.allSessionHistory, sessionIds: sessionIds
                        ))
                    )
                }
            }
            let now = Date().timeIntervalSince1970 * 1_000
            let buckets = UsageTimeline.buckets(
                events, since: now - 24 * 3_600_000, until: now
            )
            if !buckets.isEmpty {
                Section {
                    UsageTimelineChart(buckets: buckets, accent: Theme.accent(for: "claude"))
                } header: {
                    Text(L("Last 24 hours"))
                } footer: {
                    Text(L("Calls over time across every computer in this Project."))
                }
            }
            let summaries = TaskUsageHistory.summaries(events, sessionIds: sessionIds)
            let shares = UsageBreakdown.shares(summaries)
            if !shares.isEmpty {
                Section {
                    UsageBreakdownChart(shares: shares)
                } header: {
                    Text(L("Where the time went"))
                }
            }
        }
    }

    @ViewBuilder
    private func inventorySection(
        events: [CapabilityUsageEvent]
    ) -> some View {
        let computers = ProjectUsageStats.inventory(events, snapshot: snapshot)
            .filter { model.computerDisposition($0.endpointId, projectId: snapshot.projectId) != .removed }
        Section(L("Load by computer")) {
            if computers.isEmpty {
                Text(L("No computers reported yet."))
                    .font(.caption).foregroundStyle(Theme.muted)
            }
            ForEach(computers) { row in
                NavigationLink {
                    ProjectComputerUsageView(
                        endpointId: row.endpointId, snapshot: snapshot, model: model
                    )
                } label: {
                    ProjectComputerUsageRow(
                        usage: row, model: model,
                        work: ProjectComputerWork.current(
                            snapshot: snapshot, endpointId: row.endpointId, sessions: model.sessions
                        )
                    )
                }
                .accessibilityIdentifier("mesh.computer.\(row.endpointId)")
            }
        }
        let catalog = ProjectToolsSkillsPresentation.catalog(
            snapshot: snapshot,
            sessions: model.sessions + model.allSessionHistory,
            usage: events,
            added: model.addedToolItems(for: snapshot.projectId)
        )
        Section {
            if catalog.skills.isEmpty && catalog.servers.isEmpty {
                Text(L("Usage not yet observed"))
                    .font(.caption).foregroundStyle(Theme.muted)
            }
            ForEach(catalog.servers + catalog.skills) { item in
                Text([
                    item.name,
                    ProjectToolsSkillsPresentation.stateLabel(item.state),
                    item.version.map { "\(L("Desired")) \($0)" },
                    ProjectToolsSkillsPresentation.usageLabel(name: item.name, usedNames: catalog.usedNames),
                ].compactMap { $0 }.joined(separator: " · "))
                    .accessibilityIdentifier("mesh.inventory.\(item.name)")
            }
        } header: {
            Text(L("Tools"))
        } footer: {
            Text(events.isEmpty
                 ? L("Usage not yet observed")
                 : L("Touch and hold a tool to allow, ask, or deny it for this Project."))
        }
    }
}

struct ProjectComputerUsageRow: View {
    let usage: ProjectComputerUsage
    @ObservedObject var model: AppModel
    var work: [ProjectComputerWork.Item] = []

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack {
                Text(displayName).lineLimit(1)
                Spacer(minLength: 8)
                Text(String(format: L("%d×"), usage.calls))
                    .font(.caption).foregroundStyle(Theme.muted)
            }
            if let line = ProjectComputerWork.line(work) {
                Text(line).font(.caption)
                    .foregroundStyle(work.first?.working == true ? Theme.ok : Theme.muted)
                    .lineLimit(2)
            }
            if let detail {
                Text(detail).font(.caption).foregroundStyle(Theme.muted)
            }
            if usage.failures > 0 {
                Text(String(format: L("%d failed"), usage.failures))
                    .font(.caption).foregroundStyle(Theme.riskHigh)
            }
        }
        .padding(.vertical, 2)
    }

    private var displayName: String {
        model.connectionRegistry.connections
            .first { $0.id == usage.endpointId }?.displayName ?? usage.endpointId
    }

    private var detail: String? {
        let parts = [
            usage.cpuTimeMs.map { CapabilityResourceFormat.duration($0) },
            usage.peakMemoryBytes.map { CapabilityResourceFormat.bytes($0) },
        ].compactMap { $0 }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }
}

struct ProjectBindingRow: View {
    let binding: ProjectBindingSummary
    @ObservedObject var model: AppModel

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: binding.available ? "externaldrive.fill.badge.checkmark" : "externaldrive")
                .frame(width: 24).foregroundColor(binding.available ? Theme.ok : Theme.muted)
            VStack(alignment: .leading, spacing: 3) {
                Text(binding.displayName.isEmpty ? binding.repositoryId : binding.displayName)
                Text(detail).font(.caption).foregroundColor(Theme.muted).lineLimit(2)
            }
        }
        .padding(.vertical, 2)
    }

    var detail: String {
        let computer = model.connectionRegistry.connections
            .first(where: { $0.id == binding.endpointId })?.displayName
            ?? shortEndpoint(binding.endpointId)
        let revision = binding.revision.map { String($0.prefix(12)) }
        return [computer, revision].compactMap { $0 }.joined(separator: " · ")
    }

    func shortEndpoint(_ endpoint: String) -> String {
        endpoint.count <= 24 ? endpoint : "\(L("Computer")) \(endpoint.prefix(8))"
    }
}

struct ProjectIntegrationPeerRow: View {
    let peer: ProjectIntegrationPeer
    let snapshot: ProjectMeshSnapshot

    /// The far side is bound in this Project, so the Mesh can watch it.
    var bound: Bool {
        !ProjectOtherSide.otherSides(of: peer.repositoryId, in: snapshot)
            .filter { $0.peer == peer }.isEmpty
    }

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: bound ? "point.3.connected.trianglepath.dotted" : "point.3.filled.connected.trianglepath.dotted")
                .frame(width: 24).foregroundColor(bound ? Theme.ok : Theme.muted)
            VStack(alignment: .leading, spacing: 3) {
                Text("\(ProjectOtherSide.displayName(of: peer.repositoryId, in: snapshot)) → \(peer.peer)")
                Text([peer.via, ProjectOtherSide.phrase(relation: peer.relation, through: peer.through),
                      bound ? L("bound in this Project") : nil].compactMap { $0 }.joined(separator: " · "))
                    .font(.caption).foregroundColor(Theme.muted).lineLimit(2)
            }
        }
        .padding(.vertical, 2)
    }
}

/// Repositories as towers. The 2D capsules were not the graph.
struct ProjectRepoLensGraphView: View {
    let graph: ProjectRepoLensPresentation.Graph

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ProjectTowerGraphWebView(graph: graph)
                .frame(minHeight: graph.nodes.isEmpty ? 88 : 260)
                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            if !graph.nodes.isEmpty {
                ForEach(graph.nodes) { node in
                    HStack(spacing: 8) {
                        Circle()
                            .fill(node.working ? Theme.ok : Theme.muted)
                            .frame(width: 7, height: 7)
                        Text(node.title)
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(Theme.ink)
                    }
                }
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("project.graph")
        .accessibilityLabel(graph.rowDetail)
    }
}

/// WebGL towers for the Project's repositories and stated edges.
struct ProjectTowerGraphWebView: UIViewRepresentable {
    let graph: ProjectRepoLensPresentation.Graph

    func makeUIView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        config.preferences.setValue(true, forKey: "allowFileAccessFromFileURLs")
        let view = WKWebView(frame: .zero, configuration: config)
        view.isOpaque = false
        view.backgroundColor = .clear
        view.scrollView.isScrollEnabled = false
        view.scrollView.backgroundColor = .clear
        return view
    }

    func updateUIView(_ webView: WKWebView, context: Context) {
        webView.loadHTMLString(Self.html(graph), baseURL: nil)
    }

    static func html(_ graph: ProjectRepoLensPresentation.Graph) -> String {
        let nodes = graph.nodes.enumerated().map { index, node -> [String: Any] in
            let links = graph.edges.filter { $0.from == node.id || $0.to == node.id }.count
            return [
                "id": node.id,
                "title": node.title,
                "working": node.working,
                "height": node.working ? 2.4 : max(0.8, 0.7 + Double(links) * 0.35),
                "index": index,
            ]
        }
        let edges = graph.edges.map { ["from": $0.from, "to": $0.to] }
        let payload = (try? JSONSerialization.data(withJSONObject: [
            "nodes": nodes, "edges": edges,
        ])) .flatMap { String(data: $0, encoding: .utf8) } ?? "{\"nodes\":[],\"edges\":[]}"
        return """
        <!doctype html><html><head><meta charset="utf-8">
        <meta name="viewport" content="width=device-width,initial-scale=1,maximum-scale=1">
        <style>html,body,#stage{margin:0;height:100%;background:#111214;overflow:hidden}canvas{display:block;width:100%;height:100%}</style>
        </head><body><canvas id="stage"></canvas>
        <script>
        const data = \(payload);
        const canvas = document.getElementById("stage");
        const gl = canvas.getContext("webgl");
        if (!gl) { document.body.textContent = "Graph"; }
        else {
          const vs = gl.createShader(gl.VERTEX_SHADER);
          gl.shaderSource(vs, "attribute vec3 a; uniform mat4 uMV,uP; uniform vec3 uC; varying vec3 vC; void main(){ gl_Position=uP*uMV*vec4(a,1); vC=uC*(0.55+0.45*a.y); }");
          gl.compileShader(vs);
          const fs = gl.createShader(gl.FRAGMENT_SHADER);
          gl.shaderSource(fs, "precision mediump float; varying vec3 vC; void main(){ gl_FragColor=vec4(vC,1); }");
          gl.compileShader(fs);
          const prog = gl.createProgram();
          gl.attachShader(prog, vs); gl.attachShader(prog, fs); gl.linkProgram(prog);
          const a = gl.getAttribLocation(prog, "a");
          const uMV = gl.getUniformLocation(prog, "uMV");
          const uP = gl.getUniformLocation(prog, "uP");
          const uC = gl.getUniformLocation(prog, "uC");
          function box(w,h,d){
            const x=w/2,y=h,z=d/2;
            return new Float32Array([
              -x,0,-z, x,0,-z, x,y,-z, -x,0,-z, x,y,-z, -x,y,-z,
              -x,0,z, x,0,z, x,y,z, -x,0,z, x,y,z, -x,y,z,
              -x,0,-z, -x,0,z, -x,y,z, -x,0,-z, -x,y,z, -x,y,-z,
              x,0,-z, x,0,z, x,y,z, x,0,-z, x,y,z, x,y,-z,
              -x,y,-z, x,y,-z, x,y,z, -x,y,-z, x,y,z, -x,y,z,
              -x,0,-z, x,0,-z, x,0,z, -x,0,-z, x,0,z, -x,0,z
            ]);
          }
          function mul(a,b){const o=new Float32Array(16);for(let i=0;i<4;i++)for(let j=0;j<4;j++)o[i*4+j]=a[i*4]*b[j]+a[i*4+1]*b[4+j]+a[i*4+2]*b[8+j]+a[i*4+3]*b[12+j];return o;}
          function persp(f,asp,n,fa){const t=1/Math.tan(f/2);return new Float32Array([t/asp,0,0,0, 0,t,0,0, 0,0,(fa+n)/(n-fa),-1, 0,0,(2*fa*n)/(n-fa),0]);}
          function trans(x,y,z){return new Float32Array([1,0,0,0, 0,1,0,0, 0,0,1,0, x,y,z,1]);}
          function rotY(r){const c=Math.cos(r),s=Math.sin(r);return new Float32Array([c,0,-s,0, 0,1,0,0, s,0,c,0, 0,0,0,1]);}
          const n = data.nodes.length || 1;
          const ring = Math.max(1.6, n * 0.55);
          const placed = data.nodes.map((node, i) => {
            const angle = (i / n) * Math.PI * 2;
            return { ...node, x: Math.cos(angle) * ring, z: Math.sin(angle) * ring };
          });
          const byId = {};
          placed.forEach((node) => { byId[node.id] = node; });
          let rot = 0.4, drag = false, lastX = 0;
          canvas.addEventListener("pointerdown", (e) => { drag = true; lastX = e.clientX; });
          canvas.addEventListener("pointerup", () => { drag = false; });
          canvas.addEventListener("pointermove", (e) => { if (drag) { rot += (e.clientX - lastX) * 0.01; lastX = e.clientX; } });
          const buf = gl.createBuffer();
          function draw() {
            const dpr = window.devicePixelRatio || 1;
            canvas.width = canvas.clientWidth * dpr;
            canvas.height = canvas.clientHeight * dpr;
            gl.viewport(0, 0, canvas.width, canvas.height);
            gl.enable(gl.DEPTH_TEST);
            gl.clearColor(0.067, 0.071, 0.078, 1);
            gl.clear(gl.COLOR_BUFFER_BIT | gl.DEPTH_BUFFER_BIT);
            gl.useProgram(prog);
            const asp = canvas.width / Math.max(canvas.height, 1);
            gl.uniformMatrix4fv(uP, false, persp(0.9, asp, 0.4, 40));
            const view = mul(rotY(rot), trans(0, -1.2, -Math.max(6, ring * 3.1)));
            placed.forEach((node) => {
              const h = node.height;
              gl.bindBuffer(gl.ARRAY_BUFFER, buf);
              gl.bufferData(gl.ARRAY_BUFFER, box(0.7, h, 0.7), gl.DYNAMIC_DRAW);
              gl.vertexAttribPointer(a, 3, gl.FLOAT, false, 0, 0);
              gl.enableVertexAttribArray(a);
              gl.uniformMatrix4fv(uMV, false, mul(view, trans(node.x, 0, node.z)));
              gl.uniform3fv(uC, node.working ? [0.49, 0.81, 0.42] : [0.96, 0.48, 0.27]);
              gl.drawArrays(gl.TRIANGLES, 0, 36);
            });
            data.edges.forEach((edge) => {
              const from = byId[edge.from], to = byId[edge.to];
              if (!from || !to) return;
              const dx = to.x - from.x, dz = to.z - from.z;
              const len = Math.hypot(dx, dz);
              const midX = (from.x + to.x) / 2, midZ = (from.z + to.z) / 2;
              const angle = Math.atan2(dx, dz);
              gl.bindBuffer(gl.ARRAY_BUFFER, buf);
              gl.bufferData(gl.ARRAY_BUFFER, box(0.08, 0.06, len), gl.DYNAMIC_DRAW);
              gl.vertexAttribPointer(a, 3, gl.FLOAT, false, 0, 0);
              gl.uniformMatrix4fv(uMV, false, mul(view, mul(trans(midX, 0.03, midZ), rotY(angle))));
              gl.uniform3fv(uC, [0.45, 0.47, 0.52]);
              gl.drawArrays(gl.TRIANGLES, 0, 36);
            });
            rot += drag ? 0 : 0.004;
            requestAnimationFrame(draw);
          }
          draw();
        }
        </script></body></html>
        """
    }
}
