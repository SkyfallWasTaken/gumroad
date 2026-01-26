import { usePage } from "@inertiajs/react";
import * as React from "react";

import { ProductEditProvider, FullEditProps } from "$app/components/ProductEdit/ProductEditProvider";
import { ReceiptTab } from "$app/components/ProductEdit/ReceiptTab";

function ReceiptPage() {
  const props = usePage<FullEditProps>().props;

  return (
    <ProductEditProvider props={props}>
      <ReceiptTab />
    </ProductEditProvider>
  );
}

export default ReceiptPage;
