import Foundation
import UIKit

let rowHeight: CGFloat = 80.0

public class ListViewController: UITableViewController {
    private var state = ProgramState()
    
    convenience init(state: ProgramState) {
        self.init()
        self.state = state
        self.tableView.allowsSelection = false
        self.title = "Penises"
    }
        
    override public func numberOfSections(in tableView: UITableView) -> Int {
        return 1
    }
    
    override public func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        return state.eroNodes.count
    }
    
    override public func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        return EroNodeCell(node: state.eroNodes[indexPath.row])
    }
    
    public override func tableView(_ tableView: UITableView, heightForRowAt indexPath: IndexPath) -> CGFloat {
        return rowHeight
    }
    
    public override func tableView(_ tableView: UITableView, canEditRowAt indexPath: IndexPath) -> Bool {
        true
    }
    
    public override func tableView(_ tableView: UITableView, commit editingStyle: UITableViewCell.EditingStyle, forRowAt indexPath: IndexPath) {
        if editingStyle != .delete {
            return
        }
        let entry = state.eroNodes.remove(at: indexPath.row)
        entry.removeFromParentNode()
        tableView.deleteRows(at: [indexPath], with: .fade)
    }
}

class EroNodeCell: UITableViewCell {
    private let colorStack = UIStackView()

    convenience init(node: EroNode) {
        self.init()
        
        self.addSubview(colorStack)
        colorStack.translatesAutoresizingMaskIntoConstraints = false
        colorStack.widthAnchor.constraint(equalTo: self.widthAnchor).isActive = true
        colorStack.heightAnchor.constraint(equalToConstant: rowHeight).isActive = true
        colorStack.distribution = .fillProportionally
        colorStack.alignment = .fill
        
        let color1 = UIView()
        color1.translatesAutoresizingMaskIntoConstraints = false
        color1.backgroundColor = node.colorScheme.headColor
        colorStack.addArrangedSubview(color1)

        let color2 = UIView()
        color2.translatesAutoresizingMaskIntoConstraints = false
        color2.backgroundColor = node.colorScheme.shaftColor
        colorStack.addArrangedSubview(color2)

        let color3 = UIView()
        color3.translatesAutoresizingMaskIntoConstraints = false
        color3.backgroundColor = node.colorScheme.ballsColor
        colorStack.addArrangedSubview(color3)
    }
    
}
