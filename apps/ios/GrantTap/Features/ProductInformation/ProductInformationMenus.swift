import UIKit

enum ProductInformationMenus {
    static func aboutMenu(open: @escaping (ProductInformation) -> Void) -> UIMenu {
        UIMenu(title: "", identifier: .about, options: .displayInline,
               children: [action(.about, open: open)])
    }

    static func helpMenu(open: @escaping (ProductInformation) -> Void) -> UIMenu {
        UIMenu(title: L("Help"), identifier: .help,
               children: [ProductInformation.help, .pricing, .terms, .privacy, .licenses]
                .map { action($0, open: open) })
    }

    static func install(in builder: UIMenuBuilder) {
        guard builder.system == .main else { return }
        let open: (ProductInformation) -> Void = { $0.open() }
        builder.replace(menu: .about, with: aboutMenu(open: open))
        builder.replace(menu: .help, with: helpMenu(open: open))
    }

    private static func action(_ information: ProductInformation,
                               open: @escaping (ProductInformation) -> Void) -> UIAction {
        UIAction(title: information.title,
                 identifier: UIAction.Identifier("granttap.information.\(information.rawValue)")) { _ in
            open(information)
        }
    }
}
