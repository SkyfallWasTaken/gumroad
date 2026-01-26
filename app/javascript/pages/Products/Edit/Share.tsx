import { usePage } from "@inertiajs/react";
import * as React from "react";

import { ProductEditProvider, FullEditProps } from "$app/components/ProductEdit/ProductEditProvider";
import { ShareTab } from "$app/components/ProductEdit/ShareTab";

function SharePage() {
  const props = usePage<FullEditProps>().props;

  return (
    <ProductEditProvider props={props}>
      <ShareTab />
    </ProductEditProvider>
  );
}

export default SharePage;
