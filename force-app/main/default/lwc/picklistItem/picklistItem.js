import { api, LightningElement } from 'lwc';

// Single item in the multi-select dropdown
export default class PicklistItem extends LightningElement {
    // Item data (value, label, selected state)
    @api item;

    // CSS classes based on selection state
    get itemClass() {
        return `slds-media slds-listbox__option slds-listbox__option_entity slds-listbox__option_has-meta ${this.item?.selected ? 'slds-is-selected' : ''}`;
    }

    // Toggle selection on click
    handleClick() {
        if (!this.item) return;

        this.dispatchEvent(new CustomEvent('change', {
            detail: {
                item: this.item,
                selected: !this.item.selected
            }
        }));
    }
}